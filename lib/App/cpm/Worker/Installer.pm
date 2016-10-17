package App::cpm::Worker::Installer;
use strict;
use warnings;
use utf8;

use CPAN::DistnameInfo;
use CPAN::Meta;
use File::Basename 'basename';
use File::Path qw(mkpath rmtree);
use File::Spec;
use File::pushd 'pushd';
use File::Copy ();
use File::Copy::Recursive ();
use JSON::PP qw(encode_json decode_json);
use Menlo::CLI::Compat;

my $CACHED_MIRROR = sub {
    my $uri = shift;
    !!( $uri =~ m{^https?://(?:www.cpan.org|backpan.perl.org|cpan.metacpan.org)} );
};

sub work {
    my ($self, $job) = @_;
    my $type = $job->{type} || "(undef)";
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
        }
    } elsif ($type eq "configure") {
        my ($distdata, $requirements)
            = $self->configure($job); # $job->{directory}, $job->{distfile}, $job->{meta});
        if ($requirements) {
            return +{
                ok => 1,
                distdata => $distdata,
                requirements => $requirements,
            };
        }
    } elsif ($type eq "install") {
        my $ok = $self->install($job->{directory}, $job->{distdata});
        rmtree $job->{directory} if $ok; # XXX Carmel!!!
        return { ok => $ok };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new {
    my ($class, %option) = @_;
    my $menlo_base = (delete $option{menlo_base}) || "$ENV{HOME}/.perl-cpm/work";
    my $menlo_build_log = (delete $option{menlo_build_log}) || "$menlo_base/build.log";
    my $cache = (delete $option{cache}) || "$ENV{HOME}/.perl-cpm/cache";
    mkpath $menlo_base unless -d $menlo_base;
    $option{mirror} = [$option{mirror}] if ref $option{mirror} ne 'ARRAY';

    my $menlo = Menlo::CLI::Compat->new(
        base => $menlo_base,
        log  => $menlo_build_log,
        quiet => 1,
        pod2man => undef,
        # force using HTTP::Tiny
        try_wget => 0,
        try_curl => 0,
        try_lwp  => 0,
        notest   => $option{notest},
        sudo     => $option{sudo},
    );
    if (my $local_lib = delete $option{local_lib}) {
        $menlo->{self_contained} = 1;
        $menlo->setup_local_lib($menlo->maybe_abs($local_lib));
    }
    $menlo->init_tools;
    bless { %option, cache => $cache, menlo => $menlo }, $class;
}

sub menlo { shift->{menlo} }

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

    my $dir;
    my $using_cache;
    if ($source eq "git") {
        my $ref = $job->{ref} ? "\@$job->{ref}" : "";;
        for my $uri (@uri) {
            $uri .= ".git" if $uri !~ /\.git$/;
            $uri .= $ref;
            if (my $result = $self->menlo->git_uri($uri)) {
                $dir = $result->{dir};
                last;
            }
        }
    } elsif ($source eq "local") {
        for my $uri (@uri) {
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
                File::Copy::copy($uri, $basename);
                $dir = $self->menlo->unpack($basename);
                last FETCH;
            } else {
                local $self->menlo->{save_dists};
                if ($CACHED_MIRROR->($uri)) {
                    my $cache = File::Spec->catfile($self->{cache}, "authors/id/$distfile");
                    if (-f $cache) {
                        File::Copy::copy($cache, $basename);
                        $dir = $self->menlo->unpack($basename);
                        $using_cache++;
                        last FETCH;
                    } else {
                        $self->menlo->{save_dists} = $self->{cache};
                    }
                }
                $dir = $self->menlo->fetch_module({uris => [$uri], pathname => $distfile});
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

    my $requirements = $self->_extract_requirements($meta, [qw(configure)]);
    my $p = $self->menlo->extract_packages($meta, ".");
    my $provides = [map +{
        package => $_,
        version => $p->{$_}{version} || undef,
    }, sort keys %$p];

    if (!@$requirements && -f "Build.PL") {
        push @$requirements, {
            package => "Module::Build", version => "0.38",
            phase => "configure", type => "requires",
        };
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
            push @requirements, {
                package => $package, version => $reqs->{$package},
                phase => $phase, type => "requires",
            };
        }
    }
    \@requirements;
}

sub configure {
    my ($self, $job) = @_;
    my ($dir, $distfile, $meta, $source) = @{$job}{qw(directory distfile meta source)};
    my $guard = pushd $dir;
    my $menlo = $self->menlo;
    if (-f 'Build.PL') {
        $menlo->configure([ $menlo->{perl}, 'Build.PL' ], 1);
        return unless -f 'Build';
    } elsif (-f 'Makefile.PL') {
        $menlo->configure([ $menlo->{perl}, 'Makefile.PL' ], 1); # XXX depth == 1?
        return unless -f 'Makefile';
    }
    my $distdata = $self->_build_distdata($source, $distfile, $meta);
    my $requirements = [];
    my $phase = $self->{notest} ? [qw(build runtime)] : [qw(build test runtime)];
    if (my ($file) = grep -f, qw(MYMETA.json MYMETA.yml)) {
        my $mymeta = CPAN::Meta->load_file($file);
        $requirements = $self->_extract_requirements($mymeta, $phase);
    }
    return ($distdata, $requirements);
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
    my ($self, $dir, $distdata) = @_;

    my $guard = pushd $dir;
    my $menlo = $self->menlo;

    my $installed;
    if (-f 'Build') {
        $menlo->build([ $menlo->{perl}, "./Build" ], )
        && $menlo->test([ $menlo->{perl}, "./Build", "test" ], )
        && $menlo->install([ $menlo->{perl}, "./Build", "install" ], [])
        && $installed++;
    } else {
        $menlo->build([ $menlo->{make} ], )
        && $menlo->test([ $menlo->{make}, "test" ], )
        && $menlo->install([ $menlo->{make}, "install" ], [])
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
