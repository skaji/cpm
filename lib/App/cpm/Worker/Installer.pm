package App::cpm::Worker::Installer;
use strict;
use warnings;

use App::cpm::Builder::Static;
use App::cpm::Requirement;
use App::cpm::Util;
use App::cpm::Worker::Installer::Prebuilt;
use App::cpm::version;
use CPAN::DistnameInfo;
use CPAN::Meta;
use Config;
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
    my ($self, $ctx, $task) = @_;
    my $type = $task->{type} || "(undef)";
    local $ctx->{logger}{context} = $task->distvname;
    if ($type eq "fetch") {
        if (my $result = $self->fetch($ctx, $task)) {
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
            $ctx->log("Failed to fetch/configure distribution");
        }
    } elsif ($type eq "configure") {
        # $task->{directory}, $task->{distfile}, $task->{meta});
        if (my $result = $self->configure($ctx, $task)) {
            return +{
                ok => 1,
                requirements => $result->{requirements},
                static_builder => $result->{static_builder},
            };
        } else {
            $ctx->log("Failed to configure distribution");
        }
    } elsif ($type eq "install") {
        my $ok = $self->install($ctx, $task);
        my $message = $ok ? "Successfully installed distribution" : "Failed to install distribution";
        $ctx->log($message);
        return { ok => $ok, directory => $task->{directory} };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new {
    my ($class, $ctx, %option) = @_;
    $option{work_dir}  or die "work_dir option is required\n";
    $option{cache_dir} or die "cache_dir option is required\n";
    mkpath $_ for grep !-d, $option{work_dir}, $option{cache_dir};
    if ($option{local_lib}) {
        $option{local_lib} = App::cpm::Util::maybe_abs($option{local_lib});
    }

    my $need_noman_argv = !$option{man_pages} &&
        ($Config{installman1dir} || $Config{installsiteman1dir} || $Config{installman3dir} || $Config{installsiteman3dir});

    $option{prebuilt} = App::cpm::Worker::Installer::Prebuilt->new if $option{prebuilt};
    bless {
        %option,
        need_noman_argv => $need_noman_argv,
    }, $class;
}

sub _fetch_git {
    my ($self, $ctx, $uri, $ref) = @_;
    my $basename = File::Basename::basename($uri);
    $basename =~ s/\.git$//;
    $basename =~ s/[^a-zA-Z0-9_.-]/-/g;
    my $dir = File::Temp::tempdir(
        "$basename-XXXXX",
        CLEANUP => 0,
        DIR => $self->{work_dir},
    );
    $ctx->log("Cloning $uri");

    my @depth = $ref ? () : ('--depth=1');

    local $ENV{GIT_TERMINAL_PROMPT} = 0 if !exists $ENV{GIT_TERMINAL_PROMPT};
    $ctx->run_command([ 'git', 'clone', @depth, $uri, $dir ]);

    if (!-e "$dir/.git") {
        $ctx->log("Failed cloning git repository $uri");
        return;
    }
    my $guard = pushd $dir;
    if ($ref) {
        if (!$ctx->run_command([ 'git', 'checkout', $ref ])) {
            $ctx->log("Failed to checkout '$ref' in git repository $uri");
            return;
        }
    }
    chomp(my $rev = `git rev-parse --short HEAD`);
    ($dir, $rev);
}

sub enable_prebuilt {
    my ($self, $ctx, $uri) = @_;
    $self->{prebuilt} && !$self->{prebuilt}->skip($uri) && $TRUSTED_MIRROR->($uri);
}

sub fetch {
    my ($self, $ctx, $task) = @_;
    my $guard = pushd;

    my $source   = $task->{source};
    my $distfile = $task->{distfile};
    my $uri      = $task->{uri};

    if ($self->enable_prebuilt($ctx, $uri)) {
        if (my $result = $self->find_prebuilt($ctx, $uri)) {
            $ctx->log("Using prebuilt $result->{directory}");
            return $result;
        }
    }

    my ($dir, $rev, $using_cache);
    if ($source eq "git") {
        ($dir, $rev) = $self->_fetch_git($ctx, $uri, $task->{ref});
    } elsif ($source eq "local") {
        $ctx->log("Copying $uri");
        $uri =~ s{^file://}{};
        $uri = App::cpm::Util::maybe_abs($uri);
        my $basename = basename $uri;
        my $g = pushd $self->{work_dir};
        if (-d $uri) {
            my $dest = File::Temp::tempdir(
                "$basename-XXXXX",
                CLEANUP => 0,
                DIR => $self->{work_dir},
            );
            File::Copy::Recursive::dircopy($uri, $dest);
            $dir = $dest;
        } elsif (-f $uri) {
            my $dest = $basename;
            File::Copy::copy($uri, $dest);
            $dir = $self->unpack($ctx, $basename);
            $dir = File::Spec->catdir($self->{work_dir}, $dir) if $dir;
        }
    } elsif ($source =~ /^(?:cpan|https?)$/) {
        my $g = pushd $self->{work_dir};

        FETCH: {
            my $basename = basename $uri;
            if ($uri =~ s{^file://}{}) {
                $ctx->log("Copying $uri");
                File::Copy::copy($uri, $basename)
                    or last FETCH;
                $dir = $self->unpack($ctx, $basename);
            } else {
                if ($distfile and $TRUSTED_MIRROR->($uri)) {
                    my $cache = File::Spec->catfile($self->{cache_dir}, "authors/id/$distfile");
                    if (-f $cache) {
                        $ctx->log("Using cache $cache");
                        File::Copy::copy($cache, $basename);
                        $dir = $self->unpack($ctx, $basename);
                        if ($dir) {
                            $using_cache++;
                            last FETCH;
                        }
                        unlink $cache;
                    }
                }
                $dir = $self->fetch_distribution($ctx, $uri, $distfile);
            }
        }
        $dir = File::Spec->catdir($self->{work_dir}, $dir) if $dir;
    }
    return unless $dir;

    chdir $dir or die;

    my $meta = $self->_load_metafile($ctx, $distfile, 'META.json', 'META.yml');
    if (!$meta) {
        $ctx->log("Distribution does not have META.json nor META.yml");
        return;
    }
    my $provides = $self->extract_packages($ctx, $meta);

    my $req = { configure => App::cpm::Requirement->new };
    if ($self->opts_in_static_install($ctx, $meta)) {
        $ctx->log("Distribution opts in x_static_install: $meta->{x_static_install}");
    } else {
        $req = { configure => $self->_extract_configure_requirements($ctx, $meta, $distfile) };
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
    my ($self, $ctx, $uri) = @_;
    my $info = CPAN::DistnameInfo->new($uri);
    my $dir = File::Spec->catdir($self->{prebuilt_base}, $info->cpanid, $info->distvname);
    return unless -f File::Spec->catfile($dir, ".prebuilt");

    my $guard = pushd $dir;

    my $meta   = $self->_load_metafile($ctx, $uri, 'META.json', 'META.yml');
    my $mymeta = $self->_load_metafile($ctx, $uri, 'blib/meta/MYMETA.json');
    my $phase  = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];

    my %req;
    if (!$self->opts_in_static_install($ctx, $meta)) {
        # XXX Actually we don't need configure requirements for prebuilt.
        # But requires them for consistency for now.
        %req = ( configure => $self->_extract_configure_requirements($ctx, $meta, $uri) );
    }
    %req = (%req, %{$self->_extract_requirements($ctx, $mymeta, $phase)});

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
    my ($self, $ctx, $task) = @_;
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

    $ctx->log("Saving the build $task->{directory} in $dir");
    if (File::Copy::Recursive::dircopy($task->{directory}, $dir)) {
        open my $fh, ">", File::Spec->catfile($dir, ".prebuilt") or die $!;
    } else {
        warn "dircopy $task->{directory} $dir: $!";
    }
}

sub _inject_toolchain_requirements {
    my ($self, $ctx, $distfile, $requirement) = @_;
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
    my ($self, $ctx, $distfile, @file) = @_;
    my $meta;
    if (my ($file) = grep -f, @file) {
        $meta = eval { CPAN::Meta->load_file($file) };
        $ctx->log("Invalid $file: $@") if $@;
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
    my ($self, $ctx, $meta, $distfile) = @_;
    my $requirement = $self->_extract_requirements($ctx, $meta, [qw(configure)])->{configure};
    if ($requirement->empty and -f "Build.PL" and ($distfile || "") !~ m{/Module-Build-[0-9v]}) {
        $requirement->add("Module::Build" => "0.38");
    }
    if (NEED_INJECT_TOOLCHAIN_REQUIREMENTS) {
        $self->_inject_toolchain_requirements($ctx, $distfile, $requirement);
    }
    return $requirement;
}

sub _extract_requirements {
    my ($self, $ctx, $meta, $phases) = @_;
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
    my ($self, $ctx, $sub) = @_;
    return 1 if $sub->();
    return unless $self->{retry};
    Time::HiRes::sleep(0.1);
    $ctx->log("! Retrying (you can turn off this behavior by --no-retry)");
    return $sub->();
}

sub configure {
    my ($self, $ctx, $task) = @_;
    my ($dir, $distfile, $meta, $source) = @{$task}{qw(directory distfile meta source)};
    my $guard = pushd $dir;

    my $install_base = $self->{local_lib} || $self->{implicit_install_base};
    $ctx->log("Configuring distribution");
    my ($static_builder, $configure_ok);
    {
        if ($self->opts_in_static_install($ctx, $meta)) {
            $static_builder = $self->static_install_configure($ctx, $meta);
            ++$configure_ok and last;
        }
        if (-f 'Build.PL') {
            my @cmd = ($ctx->{perl}, 'Build.PL');
            push @cmd, "--install_base", $install_base if $install_base;
            push @cmd, qw(--config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=) if $self->{need_noman_argv};
            push @cmd, '--pureperl-only' if $self->{pureperl_only};
            push @cmd, @{$self->{mb_argv}} if @{$self->{mb_argv}};
            $self->_retry($ctx, sub {
                $self->_configure($ctx, \@cmd, $meta);
                -f 'Build';
            }) and ++$configure_ok and last;
        }
        if (-f 'Makefile.PL') {
            if (!$ctx->{make}) {
                $ctx->log("There is Makefile.PL, but you don't have 'make' command; you should install 'make' command first");
                last;
            }
            my @cmd = ($ctx->{perl}, 'Makefile.PL');
            push @cmd, "INSTALL_BASE=$install_base" if $install_base;
            push @cmd, qw(INSTALLMAN1DIR=none INSTALLMAN3DIR=none) if $self->{need_noman_argv};
            push @cmd, 'PUREPERL_ONLY=1' if $self->{pureperl_only};
            push @cmd, @{$self->{eumm_argv}} if @{$self->{eumm_argv}};
            $self->_retry($ctx, sub {
                $self->_configure($ctx, \@cmd, $meta);
                -f 'Makefile';
            }) and ++$configure_ok and last;
        }
    }
    return unless $configure_ok;

    my $phase = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];
    my $mymeta = $self->_load_metafile($ctx, $distfile, 'MYMETA.json', 'MYMETA.yml');
    my $req = $self->_extract_requirements($ctx, $mymeta, $phase);
    return +{
        requirements => $req,
        static_builder => $static_builder,
    };
}

sub _local_lib_env_path {
    my ($self, $ctx) = @_;
    join $Config{path_sep}, File::Spec->catdir($self->{local_lib}, "bin"), ( $ENV{PATH} ? $ENV{PATH} : () );
}

sub _local_lib_env_perl5lib {
    my ($self, $ctx) = @_;
    join $Config{path_sep}, File::Spec->catdir($self->{local_lib}, "lib", "perl5"), ( $ENV{PERL5LIB} ? $ENV{PERL5LIB} : ());
}

sub _configure {
    my ($self, $ctx, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL5_CPAN_IS_RUNNING} = $$;
    $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;
    $ENV{PERL5_CPANM_IS_RUNNING} = $$;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx, $meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path($ctx);
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib($ctx);
    }
    $ctx->run_command($cmd, $self->{configure_timeout});
}

sub static_install_configure {
    my ($self, $ctx, $meta) = @_;

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
        $ENV{PATH} = $self->_local_lib_env_path($ctx);
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib($ctx);
    }
    $builder->configure(@argv);
    return $builder;
}


sub _build {
    my ($self, $ctx, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx, $meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path($ctx);
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib($ctx);
    }
    $ctx->run_command($cmd, $self->{build_timeout});
}

sub _test {
    my ($self, $ctx, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx, $meta);
    $ENV{NONINTERACTIVE_TESTING} = 1;
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path($ctx);
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib($ctx);
    }
    $ctx->run_command($cmd, $self->{test_timeout});
}

sub _install {
    my ($self, $ctx, $cmd, $meta) = @_;
    local %ENV = %ENV;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx, $meta);
    if ($self->{local_lib}) {
        $ENV{PATH} = $self->_local_lib_env_path($ctx);
        $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib($ctx);
    }
    if (ref $cmd eq 'ARRAY' && $self->{sudo}) {
        unshift @$cmd, 'sudo';
    }
    $ctx->run_command($cmd, 0);
}

sub _use_unsafe_inc {
    my ($self, $ctx, $meta) = @_;
    if (exists $ENV{PERL_USE_UNSAFE_INC}) {
        return $ENV{PERL_USE_UNSAFE_INC};
    }
    if (exists $meta->{x_use_unsafe_inc}) {
        $ctx->log("Distribution opts in x_use_unsafe_inc: $meta->{x_use_unsafe_inc}"); # XXX
        return $meta->{x_use_unsafe_inc};
    }
    1;
}

sub opts_in_static_install {
    my ($self, $ctx, $meta) = @_;
    return if !$self->{static_install};
    return if $self->{sudo} or $self->{uninstall_shadows};
    return $meta->{x_static_install} && $meta->{x_static_install} == 1;
}

sub install {
    my ($self, $ctx, $task) = @_;
    return $self->install_prebuilt($ctx, $task) if $task->{prebuilt};

    my ($dir, $static_builder, $distvname, $meta, $provides, $distfile)
        = @{$task}{qw(directory static_builder distvname meta provides distfile)};
    my $guard = pushd $dir;

    $ctx->log("Building " . ($self->{notest} ? "" : "and testing ") . "distribution");
    my $installed;
    if ($static_builder) {
        $self->_build($ctx, sub { $static_builder->build }, $meta)
        && ($self->{notest} || $self->_test($ctx, sub { $static_builder->build("test") }, $meta))
        && $self->_install($ctx, sub { $static_builder->build("install") }, $meta)
        && $installed++;
    } elsif (-f 'Build') {
        $self->_retry($ctx, sub { $self->_build($ctx, [ $ctx->{perl}, "./Build" ], $meta)  })
        && ($self->{notest} || $self->_retry($ctx, sub { $self->_test($ctx, [ $ctx->{perl}, "./Build", "test" ], $meta) }))
        && $self->_retry($ctx, sub { $self->_install($ctx, [ $ctx->{perl}, "./Build", "install" ], $meta)  })
        && $installed++;
    } else {
        $self->_retry($ctx, sub { $self->_build($ctx, [ $ctx->{make} ], $meta)  })
        && ($self->{notest} || $self->_retry($ctx, sub { $self->_test($ctx, [ $ctx->{make}, "test" ], $meta) }))
        && $self->_retry($ctx, sub { $self->_install($ctx, [ $ctx->{make}, "install" ], $meta) })
        && $installed++;
    }

    if ($installed && $distfile) {
        $self->save_meta($ctx, $meta, $distfile, $provides);
        $self->save_prebuilt($ctx, $task) if $self->enable_prebuilt($ctx, $task->{uri});
    }
    return $installed;
}

sub install_prebuilt {
    my ($self, $ctx, $task) = @_;

    my $install_base = $self->{local_lib} || $self->{implicit_install_base};

    $ctx->log("Copying prebuilt $task->{directory}/blib");
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
    $ctx->log($stdout);
    return 1;
}

sub unpack {
    my ($self, $ctx, $file) = @_;
    $ctx->log("Unpacking $file");
    my ($dir, $err) = $ctx->{unpacker}->unpack($file);
    $ctx->log($err) if !$dir && $err;
    $dir;
}

# XXX assume current dir is distribution dir
sub extract_packages {
    my ($self, $ctx, $meta) = @_;

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
    my ($self, $ctx, $uri, $local) = @_;
    my $res = $ctx->{http}->mirror($uri, $local);
    $ctx->log($res->{status} . ($res->{reason} ? " $res->{reason}" : ""));
    return 1 if $res->{success};
    unlink $local;
    $ctx->log($res->{content}) if $res->{status} == 599;
    return;
}

sub fetch_distribution {
    my ($self, $ctx, $uri, $distfile) = @_;

    my $local = File::Spec->catfile($self->{work_dir}, File::Basename::basename($uri));
    $ctx->log("Fetching $uri");
    if (!$self->mirror($ctx, $uri, $local)) {
        $ctx->log("Failed to download $uri");
        return;
    }
    my $dir = $self->unpack($ctx, $local);
    if (!$dir) {
        return;
    }

    if ($distfile and $TRUSTED_MIRROR->($uri)) {
        my $cache = File::Spec->catfile($self->{cache_dir}, "authors/id/$distfile");
        File::Path::mkpath([ File::Basename::dirname($cache) ], 0, 0777);
        File::Copy::copy($local, $cache) or warn $!;
    }
    return $dir;
}

sub save_meta {
    my ($self, $ctx, $meta, $distfile, $provides) = @_;

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
        $ctx->{perl},
        '-MExtUtils::Install=install',
        '-e',
        qq[install({ 'blib/meta' => '$meta_target_dir' })],
    );
    $ctx->run_command(\@cmd);
}

1;
