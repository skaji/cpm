package App::cpm::CLI;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Context;
use App::cpm::DistNotation;
use App::cpm::Distribution;
use App::cpm::Logger::File;
use App::cpm::Logger;
use App::cpm::Master;
use App::cpm::Requirement;
use App::cpm::Resolver::Cascade;
use App::cpm::Resolver::MetaCPAN;
use App::cpm::Resolver::MetaDB;
use App::cpm::Util qw(WIN32 determine_home maybe_abs);
use App::cpm::Worker;
use App::cpm::version;
use App::cpm;
use CPAN::Meta;
use Command::Runner;
use Config;
use Cwd ();
use Darwin::InitObjC;
use ExtUtils::Helpers ();
use File::Copy ();
use File::Path ();
use File::Spec;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use Module::CPANfile;
use Module::cpmfile;
use Parallel::Pipes::App;

sub new ($class, %argv) {
    my $prebuilt = exists $ENV{PERL_CPM_PREBUILT} && !$ENV{PERL_CPM_PREBUILT} ? 0 : 1;
    bless {
        argv => undef,
        home => determine_home,
        cwd => Cwd::cwd(),
        workers => WIN32 ? 1 : 5,
        snapshot => "cpanfile.snapshot",
        dependency_file => undef,
        local_lib => "local",
        cpanmetadb => "https://cpanmetadb.plackperl.org/v1.0/",
        _default_mirror => 'https://cpan.metacpan.org/',
        retry => 1,
        configure_timeout => 60,
        build_timeout => 3600,
        test_timeout => 1800,
        with_requires => 1,
        with_recommends => 0,
        with_suggests => 0,
        with_configure => 0,
        with_build => 1,
        with_test => 1,
        with_runtime => 1,
        with_develop => 0,
        feature => [],
        notest => 1,
        prebuilt => $prebuilt,
        pureperl_only => 0,
        static_install => 1,
        install_all => 0,
        use_install_command => 0,
        default_resolvers => 1,
        %argv
    }, $class;
}

sub parse_options ($self, @argv) {
    local @ARGV = @argv;
    my ($mirror, @resolver, @feature);
    my $with_option = sub ($n) {
        ("with-$n", \$self->{"with_$n"}, "without-$n", sub (@) { $self->{"with_$n"} = 0 });
    };
    my @type  = qw(requires recommends suggests);
    my @phase = qw(configure build test runtime develop);

    GetOptions
        "L|local-lib-contained=s" => \($self->{local_lib}),
        "color!" => \($self->{color}),
        "g|global" => \($self->{global}),
        "mirror=s" => \$mirror,
        "v|verbose" => \($self->{verbose}),
        "w|workers=i" => \($self->{workers}),
        "target-perl=s" => \my $target_perl,
        "test!" => sub ($, $value, @) { $self->{notest} = $value ? 0 : 1 },
        "cpanfile=s" => sub ($, $value, @) { $self->{dependency_file} = { type => "cpanfile", path => $value } },
        "cpmfile=s" => sub ($, $value, @) { $self->{dependency_file} = { type => "cpmfile", path => $value } },
        "metafile=s" => sub ($, $value, @) { $self->{dependency_file} = { type => "metafile", path => $value } },
        "snapshot=s" => \($self->{snapshot}),
        "r|resolver=s@" => \@resolver,
        "default-resolvers!" => \($self->{default_resolvers}),
        "mirror-only" => \($self->{mirror_only}),
        "dev" => \($self->{dev}),
        "man-pages" => \($self->{man_pages}),
        "home=s" => \($self->{home}),
        "retry!" => \($self->{retry}),
        "exclude-vendor!" => \($self->{exclude_vendor}),
        "configure-timeout=i" => \($self->{configure_timeout}),
        "build-timeout=i" => \($self->{build_timeout}),
        "test-timeout=i" => \($self->{test_timeout}),
        "show-progress!" => \($self->{show_progress}),
        "prebuilt!" => \($self->{prebuilt}),
        "reinstall" => \($self->{reinstall}),
        "pp|pureperl|pureperl-only" => \($self->{pureperl_only}),
        "static-install!" => \($self->{static_install}),
        "install-all!" => \($self->{install_all}),
        "use-install-command!" => \($self->{use_install_command}),
        "with-all" => sub (@) { map { $self->{"with_$_"} = 1 } @type, @phase },
        (map $with_option->($_), @type),
        (map $with_option->($_), @phase),
        "feature=s@" => \@feature,
        "show-build-log-on-failure" => \($self->{show_build_log_on_failure}),
    or return 0;

    $self->{local_lib} = maybe_abs($self->{local_lib}, $self->{cwd}) if !$self->{global};
    $self->{home} = maybe_abs($self->{home}, $self->{cwd});
    $self->{resolver} = \@resolver;
    $self->{feature} = \@feature if @feature;
    $self->{mirror} = $self->normalize_mirror($mirror) if $mirror;
    $self->{color} = 1 if !defined $self->{color} && -t STDOUT;
    $self->{show_progress} = 1
        if !WIN32 && !$ENV{CI} && !$self->{verbose} && !defined $self->{show_progress} && -t STDERR;
    if ($target_perl) {
        die "--target-perl option conflicts with --global option\n" if $self->{global};
        # 5.8 is interpreted as 5.800, fix it
        $target_perl = "v$target_perl" if $target_perl =~ /^5\.[1-9]\d*$/;
        $target_perl = sprintf '%0.6f', App::cpm::version->parse($target_perl)->numify;
        $target_perl = '5.008' if $target_perl eq '5.008000';
        $self->{target_perl} = $target_perl;
    }
    if (WIN32 and $self->{workers} != 1) {
        die "The number of workers must be 1 under WIN32 environment.\n";
    }
    if ($self->{pureperl_only} or !$self->{notest} or $self->{man_pages}) {
        $self->{prebuilt} = 0;
    }

    $App::cpm::Logger::COLOR = 1 if $self->{color};
    $App::cpm::Logger::VERBOSE = 1 if $self->{verbose};

    if (@ARGV) {
        if ($ARGV[0] eq "-") {
            my $argv = $self->read_argv_from_stdin;
            return -1 if $argv->@* == 0;
            $self->{argv} = $argv;
        } else {
            $self->{argv} = \@ARGV;
        }
    } elsif (!$self->{dependency_file}) {
        $self->{dependency_file} = $self->locate_dependency_file;
    }
    return 1;
}

sub read_argv_from_stdin ($self) {
    my @argv;
    while (my $line = <STDIN>) {
        next if $line !~ /\S/;
        next if $line =~ /^\s*#/;
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        push @argv, split /\s+/, $line;
    }
    return \@argv;
}

sub _core_inc ($self) {
    [
        (!$self->{exclude_vendor} ? grep {$_} @Config{qw(vendorarch vendorlibexp)} : ()),
        @Config{qw(archlibexp privlibexp)},
    ];
}

sub _search_inc ($self) {
    return \@INC if $self->{global};

    my $base = $self->{local_lib};
    my @local_lib = (
        App::cpm::Util::maybe_abs(File::Spec->catdir($base, "lib", "perl5", $Config{archname})),
        App::cpm::Util::maybe_abs(File::Spec->catdir($base, "lib", "perl5")),
    );
    if ($self->{target_perl}) {
        return [@local_lib];
    } else {
        return [@local_lib, $self->_core_inc->@*];
    }
}

sub normalize_mirror ($self, $mirror) {
    $mirror =~ s{/*$}{/};
    return $mirror if $mirror =~ m{^https?://};
    $mirror =~ s{^file://}{};
    die "$mirror: No such directory.\n" if !-d $mirror;
    "file://" . maybe_abs($mirror, $self->{cwd});
}

sub run ($self, @argv) {
    my $cmd = shift @argv or die "Need subcommand, try `cpm --help`\n";
    $cmd = "help"    if $cmd =~ /^(-h|--help)$/;
    $cmd = "version" if $cmd =~ /^(-V|--version)$/;
    if (my $sub = $self->can("cmd_$cmd")) {
        return $self->$sub(@argv) if $cmd eq "exec";
        my $ok = $self->parse_options(@argv);
        return 1 if !$ok;
        return 0 if $ok == -1;
        return $self->$sub;
    } else {
        my $message = $cmd =~ /^-/ ? "Missing subcommand" : "Unknown subcommand '$cmd'";
        die "$message, try `cpm --help`\n";
    }
}

sub cmd_version ($self) {
    my $trial = $App::cpm::TRIAL ? '-TRIAL' : '';
    print "cpm $App::cpm::VERSION$trial ($0)\n";
    if ($App::cpm::GIT_DESCRIBE) {
        print "This is a self-contained version, $App::cpm::GIT_DESCRIBE ($App::cpm::GIT_URL)\n";
    }

    printf "perl version v%vd ($^X)\n\n", $^V;

    print "  \%Config:\n";
    for my $key (qw( archname installsitelib installsitebin installman1dir installman3dir
                     sitearchexp sitelibexp vendorarch vendorlibexp archlibexp privlibexp )) {
        print "    $key=$Config{$key}\n" if $Config{$key};
    }

    print "  \%ENV:\n";
    for my $key (grep /^PERL/, sort keys %ENV) {
        print "    $key=$ENV{$key}\n";
    }

    print "  \@INC:\n";
    for my $inc (@INC) {
        print "    $inc\n" if ref($inc) ne 'CODE';
    }

    return 0;
}

sub cmd_install ($self) {
    die "Need arguments or cpm.yml/cpanfile/Build.PL/Makefile.PL\n" if !$self->{argv} && !$self->{dependency_file};

    local %ENV = %ENV;

    File::Path::mkpath($self->{home}) if !-d $self->{home};
    my $now = time;
    my $log_file = File::Spec->catfile($self->{home}, "build.log.$now");
    my $work_dir = File::Spec->catdir($self->{home}, "work", "$now.$$");
    my $cache_dir = File::Spec->catdir($self->{home}, "cache");

    my $ctx = App::cpm::Context->new(log_file => $log_file);
    $ctx->{logger}->symlink_to("$self->{home}/build.log");
    my $trial = $App::cpm::TRIAL ? '-TRIAL' : '';
    $ctx->log("Running cpm $App::cpm::VERSION$trial ($0) on perl $Config{version} built for $Config{archname} ($^X)");
    $ctx->log("This is a self-contained version, $App::cpm::GIT_DESCRIBE ($App::cpm::GIT_URL)") if $App::cpm::GIT_DESCRIBE;
    $ctx->log("Command line arguments are: @ARGV");
    $ctx->log("Work directory is $work_dir");

    $ctx->log("You have make $ctx->{make}") if $ctx->{make};
    $ctx->log("You have $ctx->{http_description}");
    my $unpacker_desc = $ctx->{unpacker}->describe;
    for my $key (sort keys $unpacker_desc->%*) {
        $ctx->log("You have $key $unpacker_desc->{$key}");
    }

    my ($implicit_install_base, $eumm_argv, $mb_argv) = $self->_parse_builder_env;
    if ($implicit_install_base or $eumm_argv->@* or $mb_argv->@*) {
        $ctx->log("Loading configuration from PERL_MM_OPT and PERL_MB_OPT:");
        $ctx->log("  install_base: $implicit_install_base") if $implicit_install_base;
        $ctx->log("  ExtUtils::MakeMaker options: $eumm_argv->@*") if $eumm_argv->@*;
        $ctx->log("  Module::Build options: $mb_argv->@*") if $mb_argv->@*;
    }

    $ctx->log("--", `$ctx->{perl} -V`, "--");

    my $master = App::cpm::Master->new(
        core_inc => $self->_core_inc,
        search_inc => $self->_search_inc,
        global => $self->{global},
        notest => $self->{notest},
        show_progress => $self->{show_progress},
        install_all => $self->{install_all},
        (exists $self->{target_perl} ? (target_perl => $self->{target_perl}) : ()),
    );

    my ($packages, $dists, $resolver) = $self->initial_task($ctx, $master);
    return 0 if !$packages;

    my $worker = App::cpm::Worker->new(
        $ctx,
        verbose   => $self->{verbose},
        home      => $self->{home},
        work_dir  => $work_dir,
        cache_dir => $cache_dir,
        resolver  => $self->generate_resolver($ctx, $resolver),
        man_pages => $self->{man_pages},
        retry     => $self->{retry},
        prebuilt  => $self->{prebuilt},
        pureperl_only => $self->{pureperl_only},
        static_install => $self->{static_install},
        use_install_command => $self->{use_install_command},
        configure_timeout => $self->{configure_timeout},
        build_timeout     => $self->{build_timeout},
        test_timeout      => $self->{test_timeout},
        ($self->{global} ? () : (local_lib => $self->{local_lib})),
        implicit_install_base => $implicit_install_base,
        eumm_argv => $eumm_argv,
        mb_argv => $mb_argv,
    );

    $master->add_task($ctx, type => "resolve", final_target => 1, $_->%*) for $packages->@*;
    $_->final_target(1) for $dists->@*;
    $master->add_distribution($_) for $dists->@*;
    $self->install($ctx, $master, $worker, $self->{workers});
    $master->install_distributions($ctx);
    my $fail = $master->fail($ctx);
    if ($fail) {
        local $App::cpm::Logger::VERBOSE = 0;
        for my $type (qw(install resolve)) {
            App::cpm::Logger->log(result => "FAIL", type => $type, message => $_) for $fail->{$type}->@*;
        }
    }
    my $installed = $master->installed_distributions;
    warn $self->{install_all}
        ? sprintf("%d distribution%s installed.\n", $installed, $installed > 1 ? "s" : "")
        : sprintf("%d distribution%s installed (the runtime dependency closure only).\n", $installed, $installed > 1 ? "s" : "");
    $self->cleanup;

    if ($fail) {
        if ($self->{show_build_log_on_failure}) {
            File::Copy::copy($ctx->{logger}->file, \*STDERR);
        } else {
            warn "See $self->{home}/build.log for details.\n";
            warn "You may want to execute cpm with --show-build-log-on-failure,\n";
            warn "so that the build.log is automatically dumped on failure.\n";
        }
        return 1;
    } else {
        return 0;
    }
}

sub _parse_builder_env ($class) {
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
                push @mb_argv, $arg;
            }
        }
        delete $ENV{PERL_MB_OPT};
    }
    ($install_base, \@eumm_argv, \@mb_argv);
}

sub install ($self, $ctx, $master, $worker, $num) {
    Darwin::InitObjC::maybe_init();

    local $App::cpm::Logger::SILENT = $self->{show_progress} ? 1 : 0;
    my @task = $master->get_task($ctx);
    Parallel::Pipes::App->run(
        num => $num,
        init_work => sub ($pipes) {
            my @pid = sort { $a <=> $b } keys $pipes->{pipes}->%*;
            $master->enable_terminal_logger(@pid) if $self->{show_progress};
            $master->terminal_logger->use_color($self->{color}) if $self->{show_progress};
        },
        before_work => sub ($task, $pipe, @) {
            $task->in_charge($pipe->{pid});
            $master->log_task if $self->{show_progress};
        },
        work => sub ($task, @) {
            return $worker->work($ctx, $task);
        },
        after_work => sub ($result, @) {
            $master->register_result($ctx, $result);
            @task = $master->get_task($ctx);
        },
        idle_tick => $self->{show_progress} ? 0.5 : undef,
        ($self->{show_progress}
            ? (idle_work => sub { $master->log_task })
            : ()),
        tasks => \@task,
    );
    $master->finalize_terminal_logger if $self->{show_progress};
}

sub cleanup ($self) {
    my $week = time - 7*24*60*60;
    my @entry = glob "$self->{home}/build.log.*";
    if (opendir my $dh, "$self->{home}/work") {
        push @entry,
            map File::Spec->catdir("$self->{home}/work", $_),
            grep !/^\.{1,2}$/,
            readdir $dh;
    }
    for my $entry (@entry) {
        my $mtime = (stat $entry)[9];
        if ($mtime < $week) {
            if (-d $entry) {
                File::Path::rmtree($entry);
            } else {
                unlink $entry;
            }
        }
    }
}

sub initial_task ($self, $ctx, $master) {
    if (!$self->{argv}) {
        my ($requirement, $reinstall, $resolver) = $self->load_dependency_file($ctx);
        my ($is_satisfied, @need_resolve) = $master->is_satisfied($requirement);
        if (!$reinstall->@* and $is_satisfied) {
            warn "All requirements are satisfied.\n";
            return;
        } elsif (!defined $is_satisfied) {
            my ($req) = grep { $_->{package} eq "perl" } $requirement->@*;
            die sprintf "%s requires perl %s, but you have only %s\n",
                $self->{dependency_file}{path}, $req->{version_range}, $self->{target_perl} || $];
        }
        my @package = (@need_resolve, $reinstall->@*);
        return (\@package, [], $resolver);
    }

    $self->{mirror} ||= $self->{_default_mirror};

    my (@package, @dist);
    for ($self->{argv}->@*) {
        my $arg = $_; # copy
        my ($package, $dist);
        if (-d $arg || -f $arg || $arg =~ s{^file://}{}) {
            $arg = maybe_abs($arg, $self->{cwd});
            $dist = App::cpm::Distribution->new(source => "local", uri => "file://$arg", provides => []);
        } elsif ($arg =~ /(?:^git:|\.git(?:@.+)?$)/) {
            my %ref = $arg =~ s/(?<=\.git)@(.+)$// ? (ref => $1) : ();
            $dist = App::cpm::Distribution->new(source => "git", uri => $arg, provides => [], %ref);
        } elsif ($arg =~ m{^(https?|file)://}) {
            my ($source, $distfile) = ($1 eq "file" ? "local" : "http", undef);
            if (my $d = App::cpm::DistNotation->new_from_uri($arg)) {
                ($source, $distfile) = ("cpan", $d->distfile);
            }
            $dist = App::cpm::Distribution->new(
                source => $source,
                uri => $arg,
                $distfile ? (distfile => $distfile) : (),
                provides => [],
            );
        } elsif (my $d = App::cpm::DistNotation->new_from_dist($arg)) {
            $dist = App::cpm::Distribution->new(
                source => "cpan",
                uri => $d->cpan_uri($self->{mirror}),
                distfile => $d->distfile,
                provides => [],
            );
        } else {
            my ($name, $version_range, $dev);
            # copy from Menlo
            # Plack@1.2 -> Plack~"==1.2"
            $arg =~ s/^([A-Za-z0-9_:]+)@([v\d\._]+)$/$1~== $2/;
            # support Plack~1.20, DBI~"> 1.0, <= 2.0"
            if ($arg =~ /\~[v\d\._,\!<>= ]+$/) {
                ($name, $version_range) = split '~', $arg, 2;
            } else {
                $arg =~ s/[~@]dev$// and $dev++;
                $name = $arg;
            }
            $package = +{
                package => $name,
                version_range => $version_range || 0,
                dev => $dev,
                reinstall => $self->{reinstall},
            };
        }
        push @package, $package if $package;
        push @dist, $dist if $dist;
    }

    return (\@package, \@dist, undef);
}

sub locate_dependency_file ($self) {
    if (-f "cpm.yml") {
        return { type => "cpmfile", path => "cpm.yml" };
    }
    if (-f "cpanfile") {
        return { type => "cpanfile", path => "cpanfile" };
    }
    if (-f 'META.json') {
        my $meta = CPAN::Meta->load_file('META.json');
        if (!$meta->dynamic_config) {
            return { type => 'metafile', path => 'META.json' };
        }
    }
    if (-f 'Build.PL' || -f 'Makefile.PL') {
        my $build_file = -f 'Build.PL' ? 'Build.PL' : 'Makefile.PL';
        my @cmd = ($^X, $build_file);
        warn "Executing $build_file to generate MYMETA.json and to determine requirements...\n";
        local %ENV = (
            PERL5_CPAN_IS_RUNNING => 1,
            PERL5_CPANPLUS_IS_RUNNING => 1,
            PERL5_CPANM_IS_RUNNING => 1,
            PERL_MM_USE_DEFAULT => 1,
            %ENV,
        );
        if (!$self->{global}) {
            my $base = App::cpm::Util::maybe_abs($self->{local_lib});
            $ENV{PATH} = join $Config{path_sep}, File::Spec->catdir($base, "bin"), ( $ENV{PATH} ? $ENV{PATH} : () );
            $ENV{PERL5LIB} = join $Config{path_sep}, File::Spec->catdir($base, "lib", "perl5"), ( $ENV{PERL5LIB} ? $ENV{PERL5LIB} : ());
            if ($build_file eq "Makefile.PL") {
                push @cmd, "INSTALL_BASE=$base";
            } else {
                push @cmd, "--install_base", $base;
            }
        }
        my $runner = Command::Runner->new(
            command => \@cmd,
            timeout => 60,
            redirect => 1,
        );
        my $res = $runner->run;
        if ($res->{timeout}) {
            die "Error: timed out (>60s).\n$res->{stdout}";
        }
        if ($res->{result} != 0) {
            die "Error: failed to execute $build_file.\n$res->{stdout}";
        }
        if (!-f 'MYMETA.json') {
            die "Error: No MYMETA.json after executing $build_file\n";
        }
        return { type => 'metafile', path => 'MYMETA.json' };
    }
    return;
}

sub load_dependency_file ($self, $ctx) {
    my $cpmfile = do {
        my ($type, $path) = $self->{dependency_file}->@{qw(type path)};
        warn "Loading requirements from $path...\n";
        if ($type eq "cpmfile") {
            Module::cpmfile->load($path);
        } elsif ($type eq "cpanfile") {
            Module::cpmfile->from_cpanfile(Module::CPANfile->load($path));
        } elsif ($type eq "metafile") {
            Module::cpmfile->from_cpanmeta(CPAN::Meta->load_file($path));
        } else {
            die;
        }
    };
    if (!$self->{mirror}) {
        my $mirrors = $cpmfile->{_mirrors} || [];
        if ($mirrors->@*) {
            $self->{mirror} = $self->normalize_mirror($mirrors->[0]);
        } else {
            $self->{mirror} = $self->{_default_mirror};
        }
    }
    my @phase = grep $self->{"with_$_"}, qw(configure build test runtime develop);
    my @type  = grep $self->{"with_$_"}, qw(requires recommends suggests);
    my $reqs = $cpmfile->effective_requirements($self->{feature}, \@phase, \@type);

    my (@package, @reinstall);
    for my $package (sort keys $reqs->%*) {
        my $options = $reqs->{$package};
        my $req = {
            package => $package,
            version_range => $options->{version},
            dev => $options->{dev},
            reinstall => $options->{git} ? 1 : 0,
        };
        if ($options->{git}) {
            push @reinstall, $req;
        } else {
            push @package, $req;
        }
    }

    require App::cpm::Resolver::Custom;
    my $resolver = App::cpm::Resolver::Custom->new(
        $ctx,
        requirements => $reqs,
        mirror => $self->{mirror},
        from => $self->{dependency_file}{type},
    );
    return (\@package, \@reinstall, $resolver->effective ? $resolver : undef);
}

sub generate_resolver ($self, $ctx, $initial) {
    my $cascade = App::cpm::Resolver::Cascade->new($ctx);
    $cascade->add($initial) if $initial;
    if ($self->{resolver}->@*) {
        for my $r ($self->{resolver}->@*) {
            my ($klass, @argv) = split /,/, $r;
            my $resolver = $self->_generate_resolver($ctx, $klass, @argv);
            $cascade->add($resolver);
        }
    }
    return $cascade if !$self->{default_resolvers};

    if ($self->{mirror_only}) {
        require App::cpm::Resolver::02Packages;
        my $resolver = App::cpm::Resolver::02Packages->new(
            $ctx,
            mirror => $self->{mirror},
            cache => "$self->{home}/sources",
        );
        $cascade->add($resolver);
        return $cascade;
    }

    if (!$self->{argv} and -f $self->{snapshot}) {
        if (!eval { require App::cpm::Resolver::Snapshot }) {
            die "To load $self->{snapshot}, you need to install Carton::Snapshot.\n";
        }
        warn "Loading distributions from $self->{snapshot}...\n";
        my $resolver = App::cpm::Resolver::Snapshot->new(
            $ctx,
            path => $self->{snapshot},
            mirror => $self->{mirror},
        );
        $cascade->add($resolver);
    }

    my $resolver = App::cpm::Resolver::MetaCPAN->new(
        $ctx,
        $self->{dev} ? (dev => 1) : (only_dev => 1)
    );
    $cascade->add($resolver);
    $resolver = App::cpm::Resolver::MetaDB->new(
        $ctx,
        uri => $self->{cpanmetadb},
        mirror => $self->{mirror},
    );
    $cascade->add($resolver);
    if (!$self->{dev}) {
        $resolver = App::cpm::Resolver::MetaCPAN->new($ctx);
        $cascade->add($resolver);
    }

    $cascade;
}

sub _generate_resolver ($self, $ctx, $klass, @argv) {
    if ($klass =~ /^metadb$/i) {
        my ($uri, $mirror);
        if (@argv > 1) {
            ($uri, $mirror) = @argv;
        } elsif (@argv == 1) {
            $mirror = $argv[0];
        } else {
            $mirror = $self->{mirror};
        }
        return App::cpm::Resolver::MetaDB->new(
            $ctx,
            $uri ? (uri => $uri) : (),
            mirror => $self->normalize_mirror($mirror),
        );
    } elsif ($klass =~ /^metacpan$/i) {
        return App::cpm::Resolver::MetaCPAN->new($ctx, dev => $self->{dev});
    } elsif ($klass =~ /^02packages?$/i) {
        require App::cpm::Resolver::02Packages;
        my ($path, $mirror);
        if (@argv > 1) {
            ($path, $mirror) = @argv;
        } elsif (@argv == 1) {
            $mirror = $argv[0];
        } else {
            $mirror = $self->{mirror};
        }
        return App::cpm::Resolver::02Packages->new(
            $ctx,
            $path ? (path => $path) : (),
            cache => "$self->{home}/sources",
            mirror => $self->normalize_mirror($mirror),
        );
    } elsif ($klass =~ /^snapshot$/i) {
        require App::cpm::Resolver::Snapshot;
        return App::cpm::Resolver::Snapshot->new(
            $ctx,
            path => $self->{snapshot},
            mirror => @argv ? $self->normalize_mirror($argv[0]) : $self->{mirror},
        );
    }
    my $full_klass = $klass =~ s/^\+// ? $klass : "App::cpm::Resolver::$klass";
    (my $file = $full_klass) =~ s{::}{/}g;
    require "$file.pm"; # may die
    return $full_klass->new($ctx, @argv);
}

my $HELP = <<'EOF';
Usage: cpm install [OPTIONS...] ARGV...

Examples:
  # install modules into local/
  > cpm install Module1 Module2 ...

  # install modules from one of
  #  * cpm.yml
  #  * cpanfile
  #  * META.json (with dynamic_config false)
  #  * Build.PL
  #  * Makefile.PL
  > cpm install

  # install module into current @INC instead of local/
  > cpm install -g Module

  # read modules from STDIN by specifying "-" as an argument
  > cat module-list.txt | cpm install -

  # prefer TRIAL release
  > cpm install --dev Moose

  # install modules as if version of your perl is 5.8.5
  # so that modules which are not core in 5.8.5 will be installed
  > cpm install --target-perl 5.8.5

  # resolve distribution names from DARKPAN/modules/02packages.details.txt.gz
  # and fetch distributions from DARKPAN/authors/id/...
  > cpm install --resolver 02packages,http://example.com/darkpan Your::Module
  > cpm install --resolver 02packages,file:///path/to/darkpan    Your::Module

  # specify types/phases in cpmfile/cpanfile/metafile by "--with-*" and "--without-*" options
  > cpm install --with-recommends --without-test

Options:
  -w, --workers=N
        number of workers, default: 5
  -L, --local-lib-contained=DIR
        directory to install modules into, default: local/
  -g, --global
        install modules into current @INC instead of local/
  -v, --verbose
        verbose mode; you can see what is going on
      --prebuilt, --no-prebuilt
        save builds for CPAN distributions; and later, install the prebuilts if available
        default: on; you can also set $ENV{PERL_CPM_PREBUILT} false to disable this option.
        usage of --test and/or --man-pages disables this option.
      --target-perl=VERSION  (EXPERIMENTAL)
        install modules as if version is your perl is VERSION
      --mirror=URL
        base url for the CPAN mirror to use, cannot be used multiple times. Use --resolver instead.
        default: https://cpan.metacpan.org
      --pp, --pureperl-only
        prefer pureperl only build
      --static-install, --no-static-install
        enable/disable the static install, default: enable
      --install-all, --no-install-all
        install every successfully built distribution, including build/test-only dependencies.
        by default, cpm installs only the runtime dependency closure.
        default: off
      --use-install-command, --no-use-install-command
        use make install or ./Build install for final installation when available.
        default: off
  -r, --resolver=class,args (EXPERIMENTAL, will be removed or renamed)
        specify resolvers, you can use --resolver multiple times
        available classes: metadb/metacpan/02packages/snapshot
      --no-default-resolvers
        even if you specify --resolver, cpm continues using the default resolvers.
        if you just want to use your resolvers specified by --resolver,
        you should specify --no-default-resolvers too
      --reinstall
        reinstall the distribution even if you already have the latest version installed
      --dev (EXPERIMENTAL)
        resolve TRIAL distributions too
      --color, --no-color
        turn on/off color output, default: on
      --test, --no-test
        run test cases, default: no
      --man-pages
        generate man pages
      --retry, --no-retry
        retry configure/build/test/install if fails, default: retry
      --show-build-log-on-failure
        show build.log on failure, default: off
      --configure-timeout=sec, --build-timeout=sec, --test-timeout=sec
        specify configure/build/test timeout second, default: 60sec, 3600sec, 1800sec
      --show-progress, --no-show-progress
        show the terminal progress UI, default: on for interactive non-Windows non-CI terminals
      --cpmfile=path
        specify cpmfile path, default: ./cpm.yml
      --cpanfile=path
        specify cpanfile path, default: ./cpanfile
      --metafile=path
        specify META file path, default: N/A
      --snapshot=path
        specify cpanfile.snapshot path, default: ./cpanfile.snapshot
  -V, --version
        show version
  -h, --help
        show this help
      --feature=identifier
        specify the feature to enable in cpmfile/cpanfile/metafile; you can use --feature multiple times
      --with-requires,   --without-requires   (default: with)
      --with-recommends, --without-recommends (default: without)
      --with-suggests,   --without-suggests   (default: without)
      --with-configure,  --without-configure  (default: without)
      --with-build,      --without-build      (default: with)
      --with-test,       --without-test       (default: with)
      --with-runtime,    --without-runtime    (default: with)
      --with-develop,    --without-develop    (default: without)
        specify types/phases of dependencies in cpmfile/cpanfile/metafile to be installed
      --with-all
        shortcut for --with-requires, --with-recommends, --with-suggests,
        --with-configure, --with-build, --with-test, --with-runtime and --with-develop
EOF

sub cmd_help ($self) {
    print $HELP;
    return 0;
}

1;
