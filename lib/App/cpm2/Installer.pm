package App::cpm2::Installer;
use strict;
use warnings;

use App::cpm2::Installer::Fetcher;
use App::cpm2::Installer::Unpacker;
use App::cpm2::Installer::Util qw(execute);
use App::cpm2::Logger;
use CPAN::Meta;
use Cwd ();
use File::Path ();
use File::Spec;
use File::pushd ();
use IPC::Run3 ();
use Parse::LocalDistribution;

sub new {
    my $class = shift;
    my $home = File::Spec->catdir($ENV{HOME}, ".cpm2");
    my $workdir = File::Spec->catdir($home, "work", time);
    File::Path::mkpath $workdir if !-d $workdir;

    my $target = Cwd::abs_path("./local");

    my $logger = App::cpm2::Logger->new(File::Spec->catfile($workdir, "build.log"));
    my $fetcher = App::cpm2::Installer::Fetcher->new(home => File::Spec->catdir($home, "cache"));
    my $unpacker = App::cpm2::Installer::Unpacker->new(home => $workdir);
    bless {
        logger => $logger,
        target => $target,
        fetcher => $fetcher,
        unpacker => $unpacker,
    }, $class;
}

sub work {
    my ($self, $task) = @_;

    if (my $method = $self->can($task->type)) {
        my $res = $self->$method($task);
    } else {
        die;
    }
}

sub fetch {
    my ($self, $task) = @_;

    my $dist = $task->dist;

    local $self->{logger}{context} = $dist->url;
    my ($file, $err) = $self->{fetcher}->fetch($dist->url);
    if ($err) {
        $dist->err($err);
        return;
    }
    (my $dir, $err) = $self->{unpacker}->unpack($file);
    if ($err) {
        $dist->err($err);
        return;
    }

    my $meta = $self->load_metafile(map File::Spec->catfile($dir, $_), qw(META.json META.yml));
    my $requirement = $self->extract_requiremnt($meta, ['configure']);
    my $provide = $self->extract_provide($dir);

    $dist->fetched(1);
    $dist->dir($dir);
    $dist->meta($meta);
    $dist->requirement($requirement);
    $dist->provide($provide);
    return;
}

sub configure {
    my ($self, $task) = @_;

    my $dist = $task->dist;

    local $self->{logger}{context} = $dist->url;

    my $build_type = -f 'Build.PL' ? 'mb' : 'mm';
    my @cmd = ($^X, ($build_type eq 'mb' ? 'Build.PL' : 'Makefile.PL'), $self->_configure_args($build_type));

    my $ok = execute
        bin => $dist->bin,
        cmd => \@cmd,
        dir => $dist->dir,
        env => $self->_env,
        lib => $dist->lib,
        log => sub { $self->{logger}->log(@_) },
    ;

    if (!$ok || !-f 'MYMETA.json') {
        $dist->err('failed to configure');
        return;
    }

    my $mymeta = $self->load_metafile('MYMETA.json');
    my $requirement = $self->extract_requiremnt($mymeta, ['build', 'runtime']);

    $dist->configured(1);
    $dist->build_type($build_type);
    $dist->mymeta($mymeta);
    $dist->requirement($requirement);
    1;
}

sub build {
    my ($self, $task) = @_;

    my $dist = $task->dist;

    local $self->{logger}{context} = $dist->url;

    my @cmd = $dist->build_type eq 'mb' ? ('./Build', 'build') : ('make', 'build');
    my $ok = execute
        bin => $dist->bin,
        cmd => \@cmd,
        dir => $dist->dir,
        env => $self->_env,
        lib => $dist->lib,
        log => sub { $self->{logger}->log(@_) },
    ;

    if (!$ok) {
        $dist->err(1);
        return;
    }

    $self->prepare_meta($dist->dir);
    $dist->built(1);
    return;
}

sub locate {
}

sub _configure_args {
    my ($self, $build_type) = @_;

    if ($build_type eq 'mb') {
        my @args = qw(
            --config installman1dir=
            --config installman3dir=
            --config installsiteman1dir=
            --config installsiteman3dir=
        );
        push @args, "--install_base", $self->{target};

    } else {
        my @args = qw(
            INSTALLMAN1DIR=none
            INSTALLMAN3DIR=none
        );
        push @args, "INSTALL_BASE=$self->{target}";
    }
}

sub _env {
    my $self = shift;
    {
        PERL5_CPAN_IS_RUNNING => $$,
        PERL5_CPANPLUS_IS_RUNNING => $$,
        PERL_MM_USE_DEFAULT => 1,
        PERL_USE_UNSAFE_INC => 1,
        NONINTERACTIVE_TESTING => 1,
    }
}

sub extract_requiremnt {
    my ($self, $meta, $phases) = @_;
    my $prereqs = $meta->effective_prereqs->as_string_hash;

    my %requirement;
    for my $phase (@$phases) {
        my %prereq = %{ ($prereqs->{$phase}||+{})->{requires} || +{} };
        $requirement{$phase} = [ map { +{ pacakge => $_, version_range => $prereq{$_} } } keys %prereq ];
    }
    \%requirement;
}

sub load_metafile {
    my ($self, @file) = @_;
    my $meta;
    if (my ($file) = grep -f, @file) {
        $meta = eval { CPAN::Meta->load_file($file) };
    }
    die if !$meta;
    delete $meta->{x_Dist_Zilla};
    delete $meta->{x_contributors};
    $meta;
}

sub extract_provide {
    my ($self, $dir) = @_;
    my $parser = Parse::LocalDistribution->new({ALLOW_DEV_VERSION => 1});
    my $provides = $parser->parse($dir);
    for my $provide (values %$provides) {
        delete $provide->{filemtime};
        delete $provide->{infile};
        delete $provide->{version} if $provide->{version} eq 'undef';
    }
    $provides;
}

sub prepare_meta {
    my ($self, $dir) = @_;
}

1;
