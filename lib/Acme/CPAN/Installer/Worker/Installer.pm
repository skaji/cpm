package Acme::CPAN::Installer::Worker::Installer;
use strict;
use warnings;
use utf8;

use CPAN::DistnameInfo;
use CPAN::Meta;
use File::Basename 'basename';
use File::Path qw(mkpath rmtree);
use File::pushd 'pushd';
use JSON::PP qw(encode_json decode_json);
use Menlo::CLI::Compat;

sub work {
    my ($self, $job) = @_;
    my $type = $job->{type} || "(undef)";
    if ($type eq "fetch") {
        my ($directory, $meta, $configure_requirements)
            = $self->fetch($job->{distfile});
        if ($configure_requirements) {
            return +{
                ok => 1,
                directory => $directory,
                meta => $meta,
                configure_requirements => $configure_requirements,
            };
        }
    } elsif ($type eq "configure") {
        my ($distdata, $requirements)
            = $self->configure($job->{directory}, $job->{distfile}, $job->{meta});
        if ($requirements) {
            return +{
                ok => 1,
                distdata => $distdata,
                requirements => $requirements,
            };
        }
    } elsif ($type eq "install") {
        my $ok = $self->install($job->{directory}, $job->{distdata});
        return { ok => $ok };
    } else {
        die "Unknown type: $type\n";
    }
    return { ok => 0 };
}

sub new {
    my ($class, %option) = @_;
    my $menlo_base = (delete $option{menlo_base}) || "$ENV{HOME}/.experimental-installer";
    my $menlo_build_log = (delete $option{menlo_build_log}) || "$menlo_base/build.log";
    mkpath $menlo_base unless -d $menlo_base;

    my $menlo = Menlo::CLI::Compat->new(
        base => $menlo_base,
        log  => $menlo_build_log,
        quiet => 1,
        pod2man => undef,
        # force using HTTP::Tiny
        try_wget => 0,
        try_curl => 0,
        try_lwp  => 0,
    );
    if (my $local_lib = delete $option{local_lib}) {
        $menlo->{self_contained} = 1;
        $menlo->setup_local_lib($menlo->maybe_abs($local_lib));
    }
    $menlo->init_tools;
    bless { %option, menlo => $menlo }, $class;
}

sub menlo { shift->{menlo} }

sub fetch {
    my ($self, $distfile) = @_;
    my $uri = $distfile =~ /^http/i ? $distfile : "$self->{mirror}/authors/id/$distfile";
    my $dist = { uris => [ $uri ] };
    my $guard = pushd $self->menlo->{base};
    my ($old) = (basename $uri) =~ /^(.+)\.(?:tar\.gz|zip|tar\.bz2|tgz)$/;
    rmtree $old if $old && -d $old;
    my $dir = $self->menlo->fetch_module($dist)
        or return;
    chdir $dir or die;
    my ($meta, $configure_requirements) = $self->_get_configure_requirements;
    my $abs_dir = File::Spec->catdir($self->menlo->{base}, $dir);
    return ($abs_dir, $meta, $configure_requirements);
}

sub _get_configure_requirements {
    my $self = shift;
    my $meta;
    my $requirements = [];
    if (my ($file) = grep -f, qw(META.json META.yml)) {
        $meta = CPAN::Meta->load_file($file);
        $requirements = $self->_extract_requirements($meta, [qw(configure)]);
    }

    if (!@$requirements && -f "Build.PL") {
        push @$requirements, {
            package => "Module::Build", version => "0.38",
            phase => "configure", type => "requires",
        };
    }
    return ($meta ? $meta->as_struct : +{}, $requirements);
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
    my ($self, $dir, $distfile, $meta) = @_;
    my $guard = pushd $dir;
    my $menlo = $self->menlo;
    if (-f 'Build.PL') {
        $menlo->configure([ $menlo->{perl}, 'Build.PL' ], 1);
        return unless -f 'Build';
    } elsif (-f 'Makefile.PL') {
        $menlo->configure([ $menlo->{perl}, 'Makefile.PL' ], 1); # XXX depth == 1?
        return unless -f 'Makefile';
    }
    my $distdata = $self->_build_distdata($distfile, $meta);
    my $requirements = [];
    if (my ($file) = grep -f, qw(MYMETA.json MYMETA.yml)) {
        my $mymeta = CPAN::Meta->load_file($file);
        $requirements = $self->_extract_requirements($mymeta, [qw(build runtime)]);
    }
    return ($distdata, $requirements);
}

sub _build_distdata {
    my ($self, $distfile, $meta) = @_;

    my $menlo = $self->menlo;
    my $fake_state = { configured_ok => 1, use_module_build => -f "Build" };
    my $module_name = $menlo->find_module_name($fake_state) || $meta->{name};
    $module_name =~ s/-/::/g;

    my $distvname = CPAN::DistnameInfo->new($distfile)->distvname;
    my $provides = $meta->{provides} || $menlo->extract_packages($meta, ".");
    +{
        distvname => $distvname,
        pathname => $distfile,
        provides => $provides,
        version => $meta->{version} || 0,
        source => "cpan",
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
        && $menlo->install([ $menlo->{perl}, "./Build", "install" ], )
        && $installed++;
    } else {
        $menlo->build([ $menlo->{make} ], )
        && $menlo->install([ $menlo->{make}, "install" ], )
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
