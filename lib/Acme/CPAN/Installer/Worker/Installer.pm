package Acme::CPAN::Installer::Worker::Installer;
use strict;
use warnings;
use utf8;

use CPAN::Meta;
use Cwd 'cwd';
use File::Basename 'basename';
use File::Path qw(mkpath rmtree);
use File::pushd 'pushd';
use JSON::PP qw(encode_json decode_json);
use Menlo::CLI::Compat;

sub work {
    my ($self, $job) = @_;
    my $ok = $self->install($job->{distfile});
    +{ ok => $ok ? 1 : 0 };
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
    );
    $menlo->{self_contained} = 1;
    $menlo->setup_local_lib($menlo->maybe_abs( (delete $option{local_lib}) || "local"));
    $menlo->init_tools;
    bless { %option, menlo => $menlo }, $class;
}

sub menlo { shift->{menlo} }

sub install {
    my ($self, $distfile) = @_;

    my $uri = $distfile =~ /^http/i
            ? $distfile
            : "http://www.cpan.org/authors/id/$distfile";

    my $ok;
    if (my $dir = $self->_fetch_module($uri)) {
        my $guard = pushd $dir;
        $ok = $self->_install($distfile);
    }
    return $ok;
}

sub _fetch_module {
    my ($self, $uri) = @_;
    my $dist = { uris => [ $uri ] };
    my $guard = pushd;
    chdir $self->menlo->{base};
    my ($old) = (basename $uri) =~ /^(.+)\.(?:tar\.gz|zip|tar\.bz2|tgz)$/;
    rmtree $old if $old && -d $old;
    my $dir = $self->menlo->fetch_module($dist)
        or return;
    File::Spec->catdir($self->menlo->{base}, $dir);
}

sub _install {
    my ($self, $distfile) = @_;
    $self->_configure or return;

    my $dist = $self->_build_dist_hash($distfile);
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
    $menlo->save_meta($dist->{module_name}, $dist, $dist->{module_name}) if $installed && $dist;
    return $installed ? 1 : undef;
}

sub _configure {
    my $self = shift;
    my $menlo = $self->menlo;
    if (-f 'Build.PL') {
        $menlo->configure([ $menlo->{perl}, 'Build.PL' ], 1);
        return 1 if -f 'Build';
    } elsif (-f 'Makefile.PL') {
        $menlo->configure([ $menlo->{perl}, 'Makefile.PL' ], 1); # XXX depth == 1?
        return 1  if -f 'Makefile';
    }
    return;
}

sub _build_dist_hash {
    my ($self, $distfile) = @_;
    my ($file) = grep -f, "META.json", "META.yml" or return;
    my $meta = CPAN::Meta->load_file($file)->as_struct;

    my $menlo = $self->menlo;
    my $fake_state = { configured_ok => 1, use_module_build => -f "Build" };
    my $module_name = $menlo->find_module_name($fake_state) || $meta->{name};
    $module_name =~ s/-/::/g;

    my ($distvname) = $distfile =~ m{/([^/]+)\.(?:tar\.gz|zip|tar\.bz2|tgz)$};
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

1;
