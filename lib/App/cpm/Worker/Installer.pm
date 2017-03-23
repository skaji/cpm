package App::cpm::Worker::Installer;
use strict;
use warnings;
use utf8;
our $VERSION = '0.301';

use App::cpm::Logger::File;
use App::cpm::Worker::Installer::Menlo;
use CPAN::DistnameInfo;
use CPAN::Meta;
use File::Basename 'basename';
use File::Copy ();
use File::Copy::Recursive ();
use File::Path qw(mkpath rmtree);
use File::Spec;
use File::Temp ();
use File::pushd 'pushd';

use constant NEED_INJECT_TOOLCHAIN_REQS => $] < 5.016;

my $CACHED_MIRROR = sub {
    my $uri = shift;
    !!( $uri =~ m{^https?://(?:www.cpan.org|backpan.perl.org|cpan.metacpan.org)} );
};

sub work {
    my ($self, $job) = @_;
    my $type = $job->{type} || "(undef)";
    local $self->menlo->{logger}->{context} = $job->distvname;
    if ($type eq "fetch") {
        my ($directory, $meta, $configure_requirements, $provides, $using_cache)
            = $self->fetch($job);
        if ($configure_requirements) {
            return +{
                ok => 1,
                directory => $directory,
                meta => $meta,
                configure_requirements => $configure_requirements,
                provides => $provides,
                using_cache => $using_cache,
            };
        } else {
            $self->menlo->{logger}->log("Failed to fetch/configure distribution");
        }
    } elsif ($type eq "configure") {
        my ($distdata, $requirements, $static_builder)
            = $self->configure($job); # $job->{directory}, $job->{distfile}, $job->{meta});
        if ($requirements) {
            return +{
                ok => 1,
                distdata => $distdata,
                requirements => $requirements,
                static_builder => $static_builder,
            };
        } else {
            $self->menlo->{logger}->log("Failed to configure distribution");
        }
    } elsif ($type eq "install") {
        my $ok = $self->install($job);
        if ($ok) {
            $self->menlo->{logger}->log("Successfully installed distribution");
        } else {
            $self->menlo->{logger}->log("Failed to install distribution");
        }
        return { ok => $ok, directory => $job->{directory} };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new {
    my ($class, %option) = @_;
    my $logger = $option{logger} || App::cpm::Logger::File->new;
    my $base   = $option{base}   || "$ENV{HOME}/.perl-cpm/work";
    my $cache  = $option{cache}  || "$ENV{HOME}/.perl-cpm/cache";
    mkpath $_ for grep { !-d } $base, $cache;

    my $menlo = App::cpm::Worker::Installer::Menlo->new(
        base => $base,
        logger => $logger,
        quiet => 1,
        pod2man => $option{man_pages},
        notest => $option{notest},
        sudo => $option{sudo},
        mirrors => ["https://cpan.metacpan.org/"], # this is dummy
    );
    if (my $local_lib = delete $option{local_lib}) {
        $menlo->{self_contained} = 1;
        $menlo->setup_local_lib($menlo->maybe_abs($local_lib));
    }
    bless { %option, cache => $cache, menlo => $menlo }, $class;
}

sub menlo { shift->{menlo} }

sub _fetch_git {
    my ($self, $uri, $ref) = @_;
    my $dir = File::Temp::tempdir(CLEANUP => 1);
    $self->menlo->mask_output( diag_progress => "Cloning $uri" );
    $self->menlo->run_command([ 'git', 'clone', $uri, $dir ]);

    unless (-e "$dir/.git") {
        $self->menlo->diag_fail("Failed cloning git repository $uri", 1);
        return;
    }
    my $guard = pushd $dir;
    if ($ref) {
        unless ($self->menlo->run_command([ 'git', 'checkout', $ref ])) {
            $self->menlo->diag_fail("Failed to checkout '$ref' in git repository $uri\n");
            return;
        }
    }
    $self->menlo->diag_ok;
    chomp(my $rev = `git rev-parse --short HEAD`);
    ($dir, $rev);
}

my $clean = sub {
    my $uri = shift;
    my $basename = basename $uri;
    my ($old) = $basename =~ /^(.+)\.(?:tar\.gz|zip|tar\.bz2|tgz)$/;
    rmtree $old if $old && -d $old;
};

sub fetch {
    my ($self, $job) = @_;
    my $guard = pushd;

    my $source   = $job->{source};
    my $distfile = $job->{distfile};
    my @uri      = ref $job->{uri} ? @{$job->{uri}} : ($job->{uri});

    my ($dir, $rev, $using_cache);
    if ($source eq "git") {
        for my $uri (@uri) {
            ($dir, $rev) = $self->_fetch_git($uri, $job->{ref});
            last if $dir;
        }
    } elsif ($source eq "local") {
        for my $uri (@uri) {
            $self->menlo->{logger}->log("Copying $uri");
            $uri =~ s{^file://}{};
            my $basename = basename $uri;
            if (-d $uri) {
                my $dest = File::Spec->catdir(
                    $self->menlo->{base}, "$basename." . time
                );
                rmtree $dest if -d $dest;
                File::Copy::Recursive::dircopy($uri, $dest);
                $dir = $dest;
                last;
            } elsif (-f $uri) {
                my $dest = File::Spec->catfile(
                    $self->menlo->{base}, $basename,
                );
                File::Copy::copy($uri, $dest);
                my $g = pushd $self->menlo->{base};
                $clean->($uri);
                $dir = $self->menlo->unpack($basename);
                $dir = File::Spec->catdir($self->menlo->{base}, $dir);
                last;
            }
        }
    } elsif ($source =~ /^(?:cpan|https?)$/) {
        my $g = pushd $self->menlo->{base};
        FETCH: for my $uri (@uri) {
            $clean->($uri);
            my $basename = basename $uri;
            if ($uri =~ s{^file://}{}) {
                $self->menlo->{logger}->log("Copying $uri");
                File::Copy::copy($uri, $basename)
                    or next FETCH;
                $dir = $self->menlo->unpack($basename)
                    or next FETCH;
                last FETCH;
            } else {
                local $self->menlo->{save_dists};
                if ($distfile and $CACHED_MIRROR->($uri)) {
                    my $cache = File::Spec->catfile($self->{cache}, "authors/id/$distfile");
                    if (-f $cache) {
                        $self->menlo->{logger}->log("Using cache $cache");
                        File::Copy::copy($cache, $basename);
                        $dir = $self->menlo->unpack($basename);
                        unless ($dir) {
                            unlink $cache;
                            next FETCH;
                        }
                        $using_cache++;
                        last FETCH;
                    } else {
                        $self->menlo->{save_dists} = $self->{cache};
                    }
                }
                $dir = $self->menlo->fetch_module({uris => [$uri], pathname => $distfile})
                    or next FETCH;
                last FETCH;
            }
        }
        $dir = File::Spec->catdir($self->menlo->{base}, $dir) if $dir;
    }
    return unless $dir;

    chdir $dir or die;
    my ($meta, $configure_requirements, $provides)
        = $self->_get_configure_requirements($distfile);
    return ($dir, $meta, $configure_requirements, $provides, $using_cache);
}

sub _inject_toolchain_reqs {
    my ($self, $distfile, $reqs) = @_;
    $distfile ||= "";

    my %deps = map { $_->{package} => $_ } @$reqs;

    if (    -f "Makefile.PL"
        and !$deps{'ExtUtils::MakeMaker'}
        and !-f "Build.PL"
        and $distfile !~ m{/ExtUtils-MakeMaker-[0-9v]}
    ) {
        $deps{'ExtUtils::MakeMaker'} = {package => "ExtUtils::MakeMaker", version_range => '6.58'};
    }

    if (    $distfile !~ m{/ExtUtils-ParseXS-[0-9v]}
        and $distfile !~ m{/ExtUtils-MakeMaker-[0-9v]}
        and !$deps{'ExtUtils::ParseXS'}
    ) {
        $deps{'ExtUtils::ParseXS'} = {package => 'ExtUtils::ParseXS', version_range => '3.16'};
    }

    # copy from Menlo/cpanminus
    my $toolchain = CPAN::Meta::Requirements->from_string_hash({
        'Module::Build' => '0.38',
        'ExtUtils::MakeMaker' => '6.58',
        'ExtUtils::Install' => '1.46',
        'ExtUtils::ParseXS' => '3.16',
    });
    my $merge = sub {
        my $dep = shift;
        $toolchain->add_string_requirement($dep->{package}, $dep->{version_range} || 0); # may die
        $toolchain->requirements_for_module($dep->{package});
    };

    my $dep;
    if ($dep = $deps{'ExtUtils::ParseXS'}) {
        $dep->{version_range} = $merge->($dep);
    }

    if ($dep = $deps{"ExtUtils::MakeMaker"}) {
        $dep->{version_range} = $merge->($dep);
    } elsif ($dep = $deps{"Module::Build"}) {
        $dep->{version_range} = $merge->($dep);
        $dep = $deps{"ExtUtils::Install"} ||= {package => 'ExtUtils::Install', version_range => 0};
        $dep->{version_range} = $merge->($dep);
    }
    @$reqs = values %deps;
}

sub _get_configure_requirements {
    my ($self, $distfile) = @_;
    my $meta;
    if (my ($file) = grep -f, qw(META.json META.yml)) {
        $meta = eval { CPAN::Meta->load_file($file) };
    }

    unless ($meta) {
        my $d = CPAN::DistnameInfo->new($distfile);
        $meta = CPAN::Meta->new({name => $d->dist, version => $d->version});
    }

    my $p = $meta->{provides} || $self->menlo->extract_packages($meta, ".");
    my $provides = [map +{
        package => $_,
        version => $p->{$_}{version} || undef,
    }, sort keys %$p];

    my $requirements = [];
    if ($self->menlo->opts_in_static_install($meta)) {
        $self->menlo->{logger}->log("Distribution opts in x_static_install: $meta->{x_static_install}");
    } else {
        $requirements = $self->_extract_requirements($meta, [qw(configure)]);
        if (!@$requirements and -f "Build.PL" and ($distfile || "") !~ m{/Module-Build-[0-9v]}) {
            push @$requirements, {package => "Module::Build", version_range => "0.38"};
        }

        if (NEED_INJECT_TOOLCHAIN_REQS) {
            $self->_inject_toolchain_reqs($distfile, $requirements);
        }
    }
    return ($meta ? $meta->as_struct : +{}, $requirements, $provides);
}


sub _extract_requirements {
    my ($self, $meta, $phases) = @_;
    $phases = [$phases] unless ref $phases;
    my $hash = $meta->effective_prereqs->as_string_hash;
    my @requirements;
    for my $phase (@$phases) {
        my $reqs = ($hash->{$phase} || +{})->{requires} || +{};
        for my $package (sort keys %$reqs) {
            push @requirements, {package => $package, version_range => $reqs->{$package}};
        }
    }
    \@requirements;
}

sub _retry {
    my ($self, $sub) = @_;
    return 1 if $sub->();
    return unless $self->{retry};
    $self->{menlo}{logger}->log("! Retrying (you can turn off this behavior by --no-retry)");
    return $sub->();
}

sub configure {
    my ($self, $job) = @_;
    my ($dir, $distfile, $meta, $source) = @{$job}{qw(directory distfile meta source)};
    my $guard = pushd $dir;
    my $menlo = $self->menlo;

    $menlo->{logger}->log("Configuring distribution");
    my ($static_builder, $configure_ok);
    {
        if ($menlo->opts_in_static_install($meta)) {
            my $state = {};
            $menlo->static_install_configure($state, "dummy", 1);
            $static_builder = $state->{static_install};
            ++$configure_ok and last;
        }
        if (-f 'Build.PL') {
            $self->_retry(sub {
                $menlo->configure([ $menlo->{perl}, 'Build.PL' ], 1);
                -f 'Build';
            }) and ++$configure_ok and last;
        }
        if (-f 'Makefile.PL') {
            $self->_retry(sub {
                $menlo->configure([ $menlo->{perl}, 'Makefile.PL' ], 1); # XXX depth == 1?
                -f 'Makefile';
            }) and ++$configure_ok and last;
        }
    }
    return unless $configure_ok;

    my $distdata = $self->_build_distdata($source, $distfile, $meta);
    my $requirements = [];
    my $phase = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];
    if (my ($file) = grep -f, qw(MYMETA.json MYMETA.yml)) {
        my $mymeta = CPAN::Meta->load_file($file);
        $requirements = $self->_extract_requirements($mymeta, $phase);
    }
    return ($distdata, $requirements, $static_builder);
}

sub _build_distdata {
    my ($self, $source, $distfile, $meta) = @_;

    my $menlo = $self->menlo;
    my $fake_state = { configured_ok => 1, use_module_build => -f "Build" };
    my $module_name = $menlo->find_module_name($fake_state) || $meta->{name};
    $module_name =~ s/-/::/g;

    # XXX: if $source ne "cpan", then menlo->save_meta does nothing.
    # Moreover, if $distfile is git url, CPAN::DistnameInfo->distvname returns undef.
    # Then menlo->save_meta does nothing.
    my $distvname = CPAN::DistnameInfo->new($distfile)->distvname;
    my $provides = $meta->{provides} || $menlo->extract_packages($meta, ".");
    +{
        distvname => $distvname,
        pathname => $distfile,
        provides => $provides,
        version => $meta->{version} || 0,
        source => $source,
        module_name => $module_name,
    };
}

sub install {
    my ($self, $job) = @_;
    my ($dir, $distdata, $static_builder) = @{$job}{qw(directory distdata static_builder)};
    my $guard = pushd $dir;
    my $menlo = $self->menlo;

    $menlo->{logger}->log("Building " . ($menlo->{notest} ? "" : "and testing ") . "distribution");
    my $installed;
    if ($static_builder) {
        $menlo->build(sub { $static_builder->build }, )
        && $menlo->test(sub { $static_builder->build("test") }, )
        && $menlo->install(sub { $static_builder->build("install") }, [])
        && $installed++;
    } elsif (-f 'Build') {
        $self->_retry(sub { $menlo->build([ $menlo->{perl}, "./Build" ], )  })
        && $self->_retry(sub { $menlo->test([ $menlo->{perl}, "./Build", "test" ], )  })
        && $self->_retry(sub { $menlo->install([ $menlo->{perl}, "./Build", "install" ], [])  })
        && $installed++;
    } else {
        $self->_retry(sub { $menlo->build([ $menlo->{make} ], )  })
        && $self->_retry(sub { $menlo->test([ $menlo->{make}, "test" ], )  })
        && $self->_retry(sub { $menlo->install([ $menlo->{make}, "install" ], []) })
        && $installed++;
    }

    if ($installed && $distdata) {
        $menlo->save_meta(
            $distdata->{module_name},
            $distdata,
            $distdata->{module_name},
        );
    }
    return $installed;
}

1;
