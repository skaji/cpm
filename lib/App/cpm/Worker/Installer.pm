package App::cpm::Worker::Installer;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Builder::EUMM;
use App::cpm::Builder::MB;
use App::cpm::Builder::Prebuilt;
use App::cpm::Builder::Static;
use App::cpm::Requirement;
use App::cpm::Util;
use App::cpm::Worker::Installer::Prebuilt;
use App::cpm::version;
use CPAN::DistnameInfo;
use CPAN::Meta;
use Config;
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

my sub trusted_mirror ($uri) {
    !!( $uri =~ m{^https?://(?:www.cpan.org|backpan.perl.org|cpan.metacpan.org)} );
}

sub work ($self, $ctx, $task) {
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
                builder => $result->{builder},
            };
        } else {
            $ctx->log("Failed to fetch distribution");
        }
    } elsif ($type eq "configure") {
        # $task->{directory}, $task->{distfile}, $task->{meta});
        if (my $result = $self->configure($ctx, $task)) {
            return +{
                ok => 1,
                requirements => $result->{requirements},
                builder => $result->{builder},
            };
        } else {
            $ctx->log("Failed to configure distribution");
        }
    } elsif ($type eq "build") {
        my $ok = $self->build($ctx, $task);
        $ctx->log("Failed to build distribution") if !$ok;
        return {
            ok => $ok,
            builder => $task->{builder},
        };
    } elsif ($type eq "test") {
        my $ok = $self->test($ctx, $task);
        $ctx->log("Failed to test distribution") if !$ok;
        return { ok => $ok };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new ($class, $ctx, %argv) {
    $argv{work_dir}  or die "work_dir option is required\n";
    $argv{cache_dir} or die "cache_dir option is required\n";
    mkpath $_ for grep !-d, $argv{work_dir}, $argv{cache_dir};
    if ($argv{local_lib}) {
        $argv{local_lib} = App::cpm::Util::maybe_abs($argv{local_lib});
    }

    my $need_noman_argv = !$argv{man_pages} &&
        ($Config{installman1dir} || $Config{installsiteman1dir} || $Config{installman3dir} || $Config{installsiteman3dir});

    $argv{prebuilt} = App::cpm::Worker::Installer::Prebuilt->new if $argv{prebuilt};
    bless {
        %argv,
        need_noman_argv => $need_noman_argv,
    }, $class;
}

sub _fetch_git ($self, $ctx, $uri, $ref) {
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

sub enable_prebuilt ($self, $ctx, $uri) {
    $self->{prebuilt} && !$self->{prebuilt}->skip($uri) && trusted_mirror($uri);
}

sub fetch ($self, $ctx, $task) {
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
                if ($distfile and trusted_mirror($uri)) {
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
    return if !$dir;

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

sub find_prebuilt ($self, $ctx, $uri) {
    my $info = CPAN::DistnameInfo->new($uri);
    my $dir = File::Spec->catdir($self->{prebuilt_base}, $info->cpanid, $info->distvname);
    return if !-f File::Spec->catfile($dir, ".prebuilt");

    my $guard = pushd $dir;

    my $meta   = $self->_load_metafile($ctx, $uri, 'META.json', 'META.yml');
    my $mymeta = $self->_load_metafile($ctx, $uri, 'blib/meta/MYMETA.json');
    my $req = $self->_extract_requirements($ctx, $mymeta, [qw(test runtime)]);
    my $builder = App::cpm::Builder::Prebuilt->new(
        meta => $meta,
        directory => $dir,
        distvname => $info->distvname,
        local_lib => $self->{local_lib},
        install_base => $self->{local_lib} || $self->{implicit_install_base},
    );

    my $provides = do {
        open my $fh, "<", 'blib/meta/install.json' or die;
        my $json = JSON::PP::decode_json(do { local $/; <$fh> });
        my $provides = $json->{provides};
        [ map +{ package => $_, version => $provides->{$_}{version}, file => $provides->{$_}{file} }, sort keys $provides->%* ];
    };
    return +{
        directory => $dir,
        meta => $meta->as_struct,
        provides => $provides,
        prebuilt => 1,
        requirements => $req,
        builder => $builder,
    };
}

sub save_prebuilt ($self, $ctx, $task) {
    my $dir = File::Spec->catdir($self->{prebuilt_base}, $task->cpanid, $task->distvname);

    if (-d $dir and !File::Path::rmtree($dir)) {
        return;
    }

    my $parent = File::Basename::dirname($dir);
    for (1..3) {
        last if -d $parent;
        eval { File::Path::mkpath($parent) };
    }
    return if !-d $parent;

    $ctx->log("Saving the build $task->{directory} in $dir");
    if (File::Copy::Recursive::dircopy($task->{directory}, $dir)) {
        open my $fh, ">", File::Spec->catfile($dir, ".prebuilt") or die $!;
    } else {
        warn "dircopy $task->{directory} $dir: $!";
    }
}

sub _load_metafile ($self, $ctx, $distfile, @file) {
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
sub _extract_configure_requirements ($self, $ctx, $meta, $distfile) {
    my $requirement = $self->_extract_requirements($ctx, $meta, [qw(configure)])->{configure};
    if ($requirement->empty and -f "Build.PL" and ($distfile || "") !~ m{/Module-Build-[0-9v]}) {
        $requirement->add("Module::Build" => "0.38");
    }
    return $requirement;
}

sub _extract_requirements ($self, $ctx, $meta, $phases) {
    $phases = [$phases] if !ref $phases;
    my $hash = $meta->effective_prereqs->as_string_hash;

    my %req;
    for my $phase ($phases->@*) {
        my $req = App::cpm::Requirement->new;
        my $from = ($hash->{$phase} || +{})->{requires} || +{};
        for my $package (sort keys $from->%*) {
            $req->add($package, $from->{$package});
        }
        $req{$phase} = $req;
    }
    \%req;
}

sub _retry ($self, $ctx, $sub) {
    return 1 if $sub->();
    return if !$self->{retry};
    Time::HiRes::sleep(0.1);
    $ctx->log("! Retrying (you can turn off this behavior by --no-retry)");
    return $sub->();
}

sub configure ($self, $ctx, $task) {
    my ($dir, $distfile, $meta, $source) = $task->@{qw(directory distfile meta source)};
    my $guard = pushd $dir;

    $ctx->log("Configuring distribution");
    my $builder = $self->configure_builder($ctx, $task);
    return if !$builder;

    my $mymeta = $self->_load_metafile($ctx, $distfile, 'MYMETA.json', 'MYMETA.yml');
    my $req = $self->_extract_requirements($ctx, $mymeta, [qw(build test runtime)]);
    return +{
        requirements => $req,
        builder => $builder,
    };
}

sub configure_builder ($self, $ctx, $task) {
    my ($dir, $meta, $dependency_libs, $dependency_paths)
        = $task->@{qw(directory meta dependency_libs dependency_paths)};
    my @candidate = (
        ($self->{static_install} ? [ 'App::cpm::Builder::Static', $self->{mb_argv} ] : ()),
        [ 'App::cpm::Builder::MB',     $self->{mb_argv} ],
        [ 'App::cpm::Builder::EUMM',   $self->{eumm_argv} ],
    );
    for my $candidate (@candidate) {
        my ($class, $argv) = $candidate->@*;
        next if !$class->supports($meta);

        my $builder = $class->new(
            meta => $meta,
            directory => $dir,
            distfile => $task->{distfile},
            distvname => $task->{distvname},
            provides => $task->{provides},
            local_lib => $self->{local_lib},
            install_base => $self->{local_lib} || $self->{implicit_install_base},
            need_noman_argv => $self->{need_noman_argv},
            man_pages => $self->{man_pages},
            pureperl_only => $self->{pureperl_only},
            argv => $argv,
            configure_timeout => $self->{configure_timeout},
            build_timeout => $self->{build_timeout},
            test_timeout => $self->{test_timeout},
        );

        my $ok = $self->_retry($ctx, sub () { $builder->configure($ctx, $dependency_libs, $dependency_paths) });
        return $builder if $ok;
    }
    return;
}

sub opts_in_static_install ($self, $ctx, $meta) {
    return if !$self->{static_install};
    return $meta->{x_static_install} && $meta->{x_static_install} == 1;
}

sub build ($self, $ctx, $task) {
    my ($dir, $builder) = $task->@{qw(directory builder)};
    my $guard = pushd $dir;

    $ctx->log("Building distribution");
    my $ok = $self->_retry($ctx, sub () {
        $builder->build($ctx, $task->{dependency_libs}, $task->{dependency_paths});
    });
    if ($ok && !$task->{prebuilt} && $self->enable_prebuilt($ctx, $task->{uri})) {
        $self->save_prebuilt($ctx, $task);
    }
    return $ok;
}

sub test ($self, $ctx, $task) {
    my ($dir, $builder) = $task->@{qw(directory builder)};
    my $guard = pushd $dir;

    $ctx->log("Testing distribution");
    return $self->_retry($ctx, sub () {
        $builder->test($ctx, $task->{dependency_libs}, $task->{dependency_paths});
    });
}

sub unpack ($self, $ctx, $file) {
    $ctx->log("Unpacking $file");
    my ($dir, $err) = $ctx->{unpacker}->unpack($file);
    $ctx->log($err) if !$dir && $err;
    $dir;
}

# XXX assume current dir is distribution dir
sub extract_packages ($self, $ctx, $meta) {
    if (my $provides = $meta->{provides}) {
        my @out;
        for my $package (sort keys $provides->%*) {
            push @out, {
                package => $package,
                $provides->{$package}->%*,
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
    for my $package (sort keys $provides->%*) {
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

sub mirror ($self, $ctx, $uri, $local) {
    my $res = $ctx->{http}->mirror($uri, $local);
    $ctx->log($res->{status} . ($res->{reason} ? " $res->{reason}" : ""));
    return 1 if $res->{success};
    unlink $local;
    $ctx->log($res->{content}) if $res->{status} == 599;
    return;
}

sub fetch_distribution ($self, $ctx, $uri, $distfile) {
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

    if ($distfile and trusted_mirror($uri)) {
        my $cache = File::Spec->catfile($self->{cache_dir}, "authors/id/$distfile");
        File::Path::mkpath([ File::Basename::dirname($cache) ], 0, 0777);
        File::Copy::copy($local, $cache) or warn $!;
    }
    return $dir;
}

1;
