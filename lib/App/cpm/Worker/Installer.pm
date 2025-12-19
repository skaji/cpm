package App::cpm::Worker::Installer;
use strict;
use warnings;

use App::cpm::Builder::Static;
use App::cpm::HTTP;
use App::cpm::Installer::Unpacker;
use App::cpm::Logger::File;
use App::cpm::Requirement;
use App::cpm::Util;
use App::cpm::Worker::Installer::Prebuilt;
use App::cpm::version;
use CPAN::DistnameInfo;
use CPAN::Meta;
use Command::Runner;
use Config;
use ExtUtils::Helpers ();
use ExtUtils::Install ();
use ExtUtils::InstallPaths ();
use File::Basename 'basename';
use File::Copy ();
use File::Copy::Recursive ();
use File::Path qw(mkpath rmtree);
use File::Spec;
use File::Temp ();
use File::pushd 'pushd';
use JSON::PP ();
use Parse::LocalDistribution;
use Time::HiRes ();

use constant NEED_INJECT_TOOLCHAIN_REQUIREMENTS => $] < 5.018;

my $TRUSTED_MIRROR = sub {
    my $uri = shift;
    !!( $uri =~ m{^https?://(?:www.cpan.org|backpan.perl.org|cpan.metacpan.org)} );
};

sub work {
    my ($self, $task) = @_;
    my $type = $task->{type} || "(undef)";
    local $self->{logger}{context} = $task->distvname;
    if ($type eq "fetch") {
        if (my $result = $self->fetch($task)) {
            return +{
                ok => 1,
                directory => $result->{directory},
                meta => $result->{meta},
                requirements => $result->{requirements},
                provides => $result->{provides},
                using_cache => $result->{using_cache},
                prebuilt => $result->{prebuilt},
            };
        } else {
            $self->{logger}->log("Failed to fetch/configure distribution");
        }
    } elsif ($type eq "configure") {
        # $task->{directory}, $task->{distfile}, $task->{meta});
        if (my $result = $self->configure($task)) {
            return +{
                ok => 1,
                requirements => $result->{requirements},
                static_builder => $result->{static_builder},
            };
        } else {
            $self->{logger}->log("Failed to configure distribution");
        }
    } elsif ($type eq "install") {
        my $ok = $self->install($task);
        my $message = $ok ? "Successfully installed distribution" : "Failed to install distribution";
        $self->{logger}->log($message);
        return { ok => $ok, directory => $task->{directory} };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new {
    my ($class, %option) = @_;
    $option{logger} ||= App::cpm::Logger::File->new;
    $option{base}  or die "base option is required\n";
    $option{cache} or die "cache option is required\n";
    mkpath $_ for grep !-d, $option{base}, $option{cache};
    $option{logger}->log("Work directory is $option{base}");
    my $make = File::Which::which($Config{make});
    $option{logger}->log("You have make $make") if $make;
    my ($http, $http_desc) = App::cpm::HTTP->create;
    $option{logger}->log("You have $http_desc");
    my $unpacker = App::cpm::Installer::Unpacker->new;
    my $unpacker_desc = $unpacker->describe;
    for my $key (sort keys %$unpacker_desc) {
        $option{logger}->log("You have $key $unpacker_desc->{$key}");
    }
    if ($option{local_lib}) {
        $option{local_lib} = App::cpm::Util::maybe_abs($option{local_lib});
    }

    my ($implicit_install_base, $eumm_argv, $mb_argv) = $class->_parse_builder_env;
    if ($implicit_install_base or @$eumm_argv or @$mb_argv) {
        $option{logger}->log("Loading configuration from PERL_MM_OPT and PERL_MB_OPT:");
        $option{logger}->log("  install_base: $implicit_install_base") if $implicit_install_base;
        $option{logger}->log("  ExtUtils::MakeMaker options: @$eumm_argv") if @$eumm_argv;
        $option{logger}->log("  Module::Build options: @$mb_argv") if @$mb_argv;
    }
    my $need_noman_argv = !$option{man_pages} &&
        ($Config{installman1dir} || $Config{installsiteman1dir} || $Config{installman3dir} || $Config{installsiteman3dir});

    my $perl = $^X;
    $option{logger}->log("--", `$perl -V`, "--");
    $option{prebuilt} = App::cpm::Worker::Installer::Prebuilt->new if $option{prebuilt};
    bless {
        %option,
        need_noman_argv => $need_noman_argv,
        implicit_install_base => $implicit_install_base,
        eumm_argv => $eumm_argv,
        mb_argv => $mb_argv,
        perl => $perl,
        make => $make,
        unpacker => $unpacker,
        http => $http,
    }, $class;
}

sub _parse_builder_env {
    my $class = shift;
    my ($install_base, @eumm_argv, @mb_argv);
    if ($ENV{PERL_MM_OPT}) {
        my @argv = ExtUtils::Helpers::split_like_shell($ENV{PERL_MM_OPT});
        while (@argv) {
            my $arg = shift @argv;
            if ($arg =~ /^INSTALL_BASE=(.+)/) {
                $install_base = $1;
            } else {
                push @eumm_argv, $arg;
            }
        }
        delete $ENV{PERL_MM_OPT};
    }
    if ($ENV{PERL_MB_OPT}) {
        my @argv = ExtUtils::Helpers::split_like_shell($ENV{PERL_MB_OPT});
        while (@argv) {
            my $arg = shift @argv;
            if ($arg eq "--install_base") {
                $install_base = shift @argv;
            } elsif ($arg =~ /^--install_base=(.+)/) {
                $install_base = $1;
            } else {
                push @eumm_argv, $arg;
            }
        }
        delete $ENV{PERL_MB_OPT};
    }
    ($install_base, \@eumm_argv, \@mb_argv);
}

sub _fetch_git {
    my ($self, $uri, $ref) = @_;
    my $basename = File::Basename::basename($uri);
    $basename =~ s/\.git$//;
    $basename =~ s/[^a-zA-Z0-9_.-]/-/g;
    my $dir = File::Temp::tempdir(
        "$basename-XXXXX",
        CLEANUP => 0,
        DIR => $self->{base},
    );
    $self->log("Cloning $uri");

    my @depth = $ref ? () : ('--depth=1');

    local $ENV{GIT_TERMINAL_PROMPT} = 0 if !exists $ENV{GIT_TERMINAL_PROMPT};
    $self->run_command([ 'git', 'clone', @depth, $uri, $dir ]);

    if (!-e "$dir/.git") {
        $self->log("Failed cloning git repository $uri");
        return;
    }
    my $guard = pushd $dir;
    if ($ref) {
        if (!$self->run_command([ 'git', 'checkout', $ref ])) {
            $self->log("Failed to checkout '$ref' in git repository $uri");
            return;
        }
    }
    chomp(my $rev = `git rev-parse --short HEAD`);
    ($dir, $rev);
}

sub enable_prebuilt {
    my ($self, $uri) = @_;
    $self->{prebuilt} && !$self->{prebuilt}->skip($uri) && $TRUSTED_MIRROR->($uri);
}

sub fetch {
    my ($self, $task) = @_;
    my $guard = pushd;

    my $source   = $task->{source};
    my $distfile = $task->{distfile};
    my $uri      = $task->{uri};

    if ($self->enable_prebuilt($uri)) {
        if (my $result = $self->find_prebuilt($uri)) {
            $self->{logger}->log("Using prebuilt $result->{directory}");
            return $result;
        }
    }

    my ($dir, $rev, $using_cache);
    if ($source eq "git") {
        ($dir, $rev) = $self->_fetch_git($uri, $task->{ref});
    } elsif ($source eq "local") {
        $self->{logger}->log("Copying $uri");
        $uri =~ s{^file://}{};
        $uri = App::cpm::Util::maybe_abs($uri);
        my $basename = basename $uri;
        my $g = pushd $self->{base};
        if (-d $uri) {
            my $dest = File::Temp::tempdir(
                "$basename-XXXXX",
                CLEANUP => 0,
                DIR => $self->{base},
            );
            File::Copy::Recursive::dircopy($uri, $dest);
            $dir = $dest;
        } elsif (-f $uri) {
            my $dest = $basename;
            File::Copy::copy($uri, $dest);
            $dir = $self->unpack($basename);
            $dir = File::Spec->catdir($self->{base}, $dir) if $dir;
        }
    } elsif ($source =~ /^(?:cpan|https?)$/) {
        my $g = pushd $self->{base};

        FETCH: {
            my $basename = basename $uri;
            if ($uri =~ s{^file://}{}) {
                $self->{logger}->log("Copying $uri");
                File::Copy::copy($uri, $basename)
                    or last FETCH;
                $dir = $self->unpack($basename);
            } else {
                if ($distfile and $TRUSTED_MIRROR->($uri)) {
                    my $cache = File::Spec->catfile($self->{cache}, "authors/id/$distfile");
                    if (-f $cache) {
                        $self->{logger}->log("Using cache $cache");
                        File::Copy::copy($cache, $basename);
                        $dir = $self->unpack($basename);
                        if ($dir) {
                            $using_cache++;
                            last FETCH;
                        }
                        unlink $cache;
                    }
                }
                $dir = $self->fetch_distribution($uri, $distfile);
            }
        }
        $dir = File::Spec->catdir($self->{base}, $dir) if $dir;
    }
    return unless $dir;

    chdir $dir or die;

    my @accepted_meta_files = ('META.json', 'META.yml', 'MYMETA.json', 'MYMETA.yml');

    if (!grep -f, \@accepted_meta_files && grep -f, [ 'Makefile.PL', 'Build.PL' ]) {
        my $makefile = (-f 'Makefile.PL' ? 'Makefile' : 'Build');
        $self->{logger}->log("Configuring distribution via $makefile.PL");
        my @cmd = ($self->{menlo}->{perl}, "$makefile.PL");
        push @cmd, 'PUREPERL_ONLY=1' if $self->{pureperl_only};
        $self->_retry(sub {
            $self->{menlo}->configure(\@cmd, $self->{menlo_dist}, 1);
            -f $makefile;
        });
    }

    my $meta = $self->_load_metafile($distfile, @accepted_meta_files);
    if (!$meta) {
        $self->{logger}->log("Distribution lacks both META.json and META.yml files, and neither MYMETA.json nor MYMETA.yml can be generated");
        return;
    }
    my $provides = $self->extract_packages($meta);

    my $req = { configure => App::cpm::Requirement->new };
    if ($self->opts_in_static_install($meta)) {
        $self->{logger}->log("Distribution opts in x_static_install: $meta->{x_static_install}");
    } else {
        $req = { configure => $self->_extract_configure_requirements($meta, $distfile) };
    }

    return +{
        directory => $dir,
        meta => $meta,
        requirements => $req,
        provides => $provides,
        using_cache => $using_cache,
    };
}

sub find_prebuilt {
    my ($self, $uri) = @_;
    my $info = CPAN::DistnameInfo->new($uri);
    my $dir = File::Spec->catdir($self->{prebuilt_base}, $info->cpanid, $info->distvname);
    return unless -f File::Spec->catfile($dir, ".prebuilt");

    my $guard = pushd $dir;

    my $meta   = $self->_load_metafile($uri, 'META.json', 'META.yml');
    my $mymeta = $self->_load_metafile($uri, 'blib/meta/MYMETA.json');
    my $phase  = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];

    my %req;
    if (!$self->opts_in_static_install($meta)) {
        # XXX Actually we don't need configure requirements for prebuilt.
        # But requires them for consistency for now.
        %req = ( configure => $self->_extract_configure_requirements($meta, $uri) );
    }
    %req = (%req, %{$self->_extract_requirements($mymeta, $phase)});

    my $provides = do {
        open my $fh, "<", 'blib/meta/install.json' or die;
        my $json = JSON::PP::decode_json(do { local $/; <$fh> });
        my $provides = $json->{provides};
        [ map +{ package => $_, version => $provides->{$_}{version}, file => $provides->{$_}{file} }, sort keys %$provides ];
    };
    return +{
        directory => $dir,
        meta => $meta->as_struct,
        provides => $provides,
        prebuilt => 1,
        requirements => \%req,
    };
}

sub save_prebuilt {
    my ($self, $task) = @_;
    my $dir = File::Spec->catdir($self->{prebuilt_base}, $task->cpanid, $task->distvname);

    if (-d $dir and !File::Path::rmtree($dir)) {
        return;
    }

    my $parent = File::Basename::dirname($dir);
    for (1..3) {
        last if -d $parent;
        eval { File::Path::mkpath($parent) };
    }
    return unless -d $parent;

    $self->{logger}->log("Saving the build $task->{directory} in $dir");
    if (File::Copy::Recursive::dircopy($task->{directory}, $dir)) {
        open my $fh, ">", File::Spec->catfile($dir, ".prebuilt") or die $!;
    } else {
        warn "dircopy $task->{directory} $dir: $!";
    }
}

sub _inject_toolchain_requirements {
    my ($self, $distfile, $requirement) = @_;
    $distfile ||= "";

    if (    -f "Makefile.PL"
        and !$requirement->has('ExtUtils::MakeMaker')
        and !-f "Build.PL"
        and $distfile !~ m{/ExtUtils-MakeMaker-[0-9v]}
    ) {
        $requirement->add('ExtUtils::MakeMaker');
    }
    if ($requirement->has('Module::Build')) {
        $requirement->add('ExtUtils::Install');
    }

    my %inject = (
        'Module::Build' => '0.38',
        'ExtUtils::MakeMaker' => '6.64',
        'ExtUtils::Install' => '1.46',
    );

    for my $package (sort keys %inject) {
        $requirement->has($package) or next;
        $requirement->add($package, $inject{$package});
    }
    $requirement;
}

sub _load_metafile {
    my ($self, $distfile, @file) = @_;
    my $meta;
    if (my ($file) = grep -f, @file) {
        $meta = eval { CPAN::Meta->load_file($file) };
        $self->{logger}->log("Invalid $file: $@") if $@;
    }

    if (!$meta and $distfile) {
        my $d = CPAN::DistnameInfo->new($distfile);
        $meta = CPAN::Meta->new({name => $d->dist, version => $d->version});
    }
    $meta;
}

# XXX Assume current directory is distribution directory
# because the test "-f Build.PL" or similar is present
sub _extract_configure_requirements {
    my ($self, $meta, $distfile) = @_;
    my $requirement = $self->_extract_requirements($meta, [qw(configure)])->{configure};
    if ($requirement->empty and -f "Build.PL" and ($distfile || "") !~ m{/Module-Build-[0-9v]}) {
        $requirement->add("Module::Build" => "0.38");
    }
    if (NEED_INJECT_TOOLCHAIN_REQUIREMENTS) {
        $self->_inject_toolchain_requirements($distfile, $requirement);
    }
    return $requirement;
}

sub _extract_requirements {
    my ($self, $meta, $phases) = @_;
    $phases = [$phases] unless ref $phases;
    my $hash = $meta->effective_prereqs->as_string_hash;

    my %req;
    for my $phase (@$phases) {
        my $req = App::cpm::Requirement->new;
        my $from = ($hash->{$phase} || +{})->{requires} || +{};
        for my $package (sort keys %$from) {
            $req->add($package, $from->{$package});
        }
        $req{$phase} = $req;
    }
    \%req;
}

sub _retry {
    my ($self, $sub) = @_;
    return 1 if $sub->();
    return unless $self->{retry};
    Time::HiRes::sleep(0.1);
    $self->{logger}->log("! Retrying (you can turn off this behavior by --no-retry)");
    return $sub->();
}

sub configure {
    my ($self, $task) = @_;
    my ($dir, $distfile, $meta, $source) = @{$task}{qw(directory distfile meta source)};
    my $guard = pushd $dir;

    my $install_base = $self->{local_lib} || $self->{implicit_install_base};
    $self->{logger}->log("Configuring distribution");
    my ($static_builder, $configure_ok);
    {
        if ($self->opts_in_static_install($meta)) {
            $static_builder = $self->static_install_configure($meta);
            ++$configure_ok and last;
        }
        if (-f 'Build.PL') {
            my @cmd = ($self->{perl}, 'Build.PL');
            push @cmd, "--install_base", $install_base if $install_base;
            push @cmd, qw(--config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=) if $self->{need_noman_argv};
            push @cmd, '--pureperl-only' if $self->{pureperl_only};
            push @cmd, @{$self->{mb_argv}} if @{$self->{mb_argv}};
            $self->_retry(sub {
                $self->_configure(\@cmd, $meta);
                -f 'Build';
            }) and ++$configure_ok and last;
        }
        if (-f 'Makefile.PL') {
            if (!$self->{make}) {
                $self->{logger}->log("There is Makefile.PL, but you don't have 'make' command; you should install 'make' command first");
                last;
            }
            my @cmd = ($self->{perl}, 'Makefile.PL');
            push @cmd, "INSTALL_BASE=$install_base" if $install_base;
            push @cmd, qw(INSTALLMAN1DIR=none INSTALLMAN3DIR=none) if $self->{need_noman_argv};
            push @cmd, 'PUREPERL_ONLY=1' if $self->{pureperl_only};
            push @cmd, @{$self->{eumm_argv}} if @{$self->{eumm_argv}};
            $self->_retry(sub {
                $self->_configure(\@cmd, $meta);
                -f 'Makefile';
            }) and ++$configure_ok and last;
        }
    }
    return unless $configure_ok;

    my $phase = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];
    my $mymeta = $self->_load_metafile($distfile, 'MYMETA.json', 'MYMETA.yml');
    my $req = $self->_extract_requirements($mymeta, $phase);
    return +{
        requirements => $req,
        static_builder => $static_builder,
    };
}

sub _local_lib_env_path {
    my $self = shift;
    join $Config{path_sep}, File::Spec->catdir($self->{local_lib}, "bin"), ( $ENV{PATH} ? $ENV{PATH} : () );
}

sub _local_lib_env_perl5lib {
    my $self = shift;
    join $Config{path_sep}, File::Spec->catdir($self->{local_lib}, "lib", "perl5"), ( $ENV{PERL5LIB} ? $ENV{PERL5LIB} : ());
}

sub _configure {
    my ($self, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL5_CPAN_IS_RUNNING} = $$;
    $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;
    $ENV{PERL5_CPANM_IS_RUNNING} = $$;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path;
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
    }
    $self->run_timeout($cmd, $self->{configure_timeout});
}

sub static_install_configure {
    my ($self, $meta) = @_;

    my $builder = App::cpm::Builder::Static->new(meta => $meta);
    my @argv;
    if (my $install_base = $self->{local_lib} || $self->{implicit_install_base}) {
        push @argv, "--install_base", $install_base;
    }
    if ($self->{need_noman_argv}) {
        push @argv, qw(--config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=);
    }
    if ($self->{pureperl_only}) {
        push @argv, '--pureperl-only';
    }
    if (@{$self->{mb_argv}}) {
        push @argv, @{$self->{mb_argv}};
    }
    local %ENV = %ENV;
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path;
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
    }
    $builder->configure(@argv);
    return $builder;
}


sub _build {
    my ($self, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path;
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
    }
    $self->run_timeout($cmd, $self->{build_timeout});
}

sub _test {
    my ($self, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($meta);
    $ENV{NONINTERACTIVE_TESTING} = 1;
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path;
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
    }
    $self->run_timeout($cmd, $self->{test_timeout});
}

sub _install {
    my ($self, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path;
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
    }
    if (ref $cmd eq 'ARRAY' && $self->{sudo}) {
        unshift @$cmd, 'sudo';
    }
    $self->run_timeout($cmd, 0);
}

sub _use_unsafe_inc {
    my ($self, $meta) = @_;
    if (exists $ENV{PERL_USE_UNSAFE_INC}) {
        return $ENV{PERL_USE_UNSAFE_INC};
    }
    if (exists $meta->{x_use_unsafe_inc}) {
        $self->log("Distribution opts in x_use_unsafe_inc: $meta->{x_use_unsafe_inc}"); # XXX
        return $meta->{x_use_unsafe_inc};
    }
    1;
}

sub opts_in_static_install {
    my ($self, $meta) = @_;
    return if !$self->{static_install};
    return if $self->{sudo} or $self->{uninstall_shadows};
    return $meta->{x_static_install} && $meta->{x_static_install} == 1;
}

sub install {
    my ($self, $task) = @_;
    return $self->install_prebuilt($task) if $task->{prebuilt};

    my ($dir, $static_builder, $distvname, $meta, $provides, $distfile)
        = @{$task}{qw(directory static_builder distvname meta provides distfile)};
    my $guard = pushd $dir;

    $self->{logger}->log("Building " . ($self->{notest} ? "" : "and testing ") . "distribution");
    my $installed;
    if ($static_builder) {
        $self->_build(sub { $static_builder->build }, $meta)
        && ($self->{notest} || $self->_test(sub { $static_builder->build("test") }, $meta))
        && $self->_install(sub { $static_builder->build("install") }, $meta)
        && $installed++;
    } elsif (-f 'Build') {
        $self->_retry(sub { $self->_build([ $self->{perl}, "./Build" ], $meta)  })
        && ($self->{notest} || $self->_retry(sub { $self->_test([ $self->{perl}, "./Build", "test" ], $meta) }))
        && $self->_retry(sub { $self->_install([ $self->{perl}, "./Build", "install" ], $meta)  })
        && $installed++;
    } else {
        $self->_retry(sub { $self->_build([ $self->{make} ], $meta)  })
        && ($self->{notest} || $self->_retry(sub { $self->_test([ $self->{make}, "test" ], $meta) }))
        && $self->_retry(sub { $self->_install([ $self->{make}, "install" ], $meta) })
        && $installed++;
    }

    if ($installed && $distfile) {
        $self->save_meta($meta, $distfile, $provides);
        $self->save_prebuilt($task) if $self->enable_prebuilt($task->{uri});
    }
    return $installed;
}

sub install_prebuilt {
    my ($self, $task) = @_;

    my $install_base = $self->{local_lib} || $self->{implicit_install_base};

    $self->{logger}->log("Copying prebuilt $task->{directory}/blib");
    my $guard = pushd $task->{directory};
    my $paths = ExtUtils::InstallPaths->new(
        dist_name => $task->distname, # this enables the installation of packlist
        $install_base ? (install_base => $install_base) : (),
    );
    my $install_base_meta = $install_base ? File::Spec->catdir($install_base, "lib", "perl5") : $Config{sitelibexp};
    my $meta_target_dir = File::Spec->catdir($install_base_meta, $Config{archname}, ".meta", $task->distvname);

    open my $fh, ">", \my $stdout;
    {
        local *STDOUT = $fh;
        ExtUtils::Install::install([
            from_to => $paths->install_map,
            verbose => 0,
            dry_run => 0,
            uninstall_shadows => 0,
            skip => undef,
            always_copy => 1,
            result => \my %result,
        ]);
        ExtUtils::Install::install({
            'blib/meta' => $meta_target_dir,
        });
    }
    $self->{logger}->log($stdout);
    return 1;
}

sub log {
    my $self = shift;
    $self->{logger}->log(@_);
}

sub run_command {
    my ($self, $cmd) = @_;
    $self->run_timeout($cmd, 0);
}

sub run_timeout {
    my ($self, $cmd, $timeout) = @_;

    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->log("Executing $str") if $str;

    my $runner = Command::Runner->new(
        command => $cmd,
        keep => 0,
        redirect => 1,
        timeout => $timeout,
        stdout => sub { $self->log(@_) },
    );
    my $res = $runner->run;
    if ($res->{timeout}) {
        $self->log("Timed out (> ${timeout}s).");
        return;
    }
    my $result = $res->{result};
    ref $cmd eq 'CODE' ? $result : $result == 0;
}

sub unpack {
    my ($self, $file) = @_;
    $self->log("Unpacking $file");
    my ($dir, $err) = $self->{unpacker}->unpack($file);
    $self->log($err) if !$dir && $err;
    $dir;
}

# XXX assume current dir is distribution dir
sub extract_packages {
    my ($self, $meta) = @_;

    if (my $provides = $meta->{provides}) {
        my @out;
        for my $package (sort keys %$provides) {
            push @out, {
                package => $package,
                %{$provides->{$package}},
            };
        }
        return \@out;
    }

    my $parser = Parse::LocalDistribution->new({
        META_CONTENT => $meta,
        UNSAFE => 1,
        ALLOW_DEV_VERSION => 1,
    });

    my $provides = $parser->parse(".");
    my @out;
    for my $package (sort keys %$provides) {
        my $info = $provides->{$package};
        (my $file = $info->{infile}) =~ s{^\./}{};
        push @out, {
            package => $package,
            file => $file,
            ($info->{version} eq 'undef' ? () : (version => $info->{version})),
        };
    }
    \@out;
}

sub mirror {
    my ($self, $uri, $local) = @_;
    my $res = $self->{http}->mirror($uri, $local);
    $self->log($res->{status} . ($res->{reason} ? " $res->{reason}" : ""));
    return 1 if $res->{success};
    unlink $local;
    $self->log($res->{content}) if $res->{status} == 599;
    return;
}

sub fetch_distribution {
    my ($self, $uri, $distfile) = @_;

    my $local = File::Spec->catfile($self->{base}, File::Basename::basename($uri));
    $self->log("Fetching $uri");
    if (!$self->mirror($uri, $local)) {
        $self->log("Failed to download $uri");
        return;
    }
    my $dir = $self->unpack($local);
    if (!$dir) {
        return;
    }

    if ($distfile and $TRUSTED_MIRROR->($uri)) {
        my $cache = File::Spec->catfile($self->{cache}, "authors/id/$distfile");
        File::Path::mkpath([ File::Basename::dirname($cache) ], 0, 0777);
        File::Copy::copy($local, $cache) or warn $!;
    }
    return $dir;
}

sub save_meta {
    my ($self, $meta, $distfile, $provides) = @_;

    my $install_base = $self->{local_lib} || $self->{implicit_install_base};
    my $install_base_meta = $install_base ? File::Spec->catdir($install_base, "lib", "perl5") : $Config{sitelibexp};

    my %provides2 = map {
        my $package = $_->{package};
        my %info;
        $info{file} = $_->{file};
        $info{version} = $_->{version} if $_->{version};
        ($package, \%info);
    } @$provides;

    my $distvname = CPAN::DistnameInfo->new($distfile)->distvname;
    (my $name = $meta->{name}) =~ s/-/::/g;
    my %data = (
        name => $name,
        target => $name,
        version => $meta->{version},
        dist => $distvname,
        pathname => $distfile,
        provides => \%provides2,
    );

    File::Path::mkpath("blib/meta", 0, 0777);
    open my $fh, ">", "blib/meta/install.json" or die $!;
    print {$fh} JSON::PP->new->canonical->encode(\%data) . "\n";
    close $fh;

    File::Copy::copy("MYMETA.json", "blib/meta/MYMETA.json") or die $!;

    my $meta_target_dir = File::Spec->catdir($install_base_meta, $Config{archname}, ".meta", $distvname);
    my @cmd = (
        ($self->{sudo} ? 'sudo' : ()),
        $self->{perl},
        '-MExtUtils::Install=install',
        '-e',
        qq[install({ 'blib/meta' => '$meta_target_dir' })],
    );
    $self->run_command(\@cmd);
}

1;
