package App::cpm2::Installer;
use strict;
use warnings;

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
    File::Path::mkpath $home if !-d $home;
    my $file = File::Spec->catfile($home, "build.log." . time);
    my $logger = App::cpm2::Logger->new($file);
    my $target = Cwd::abs_path("./local");
    bless { home => $home, logger => $logger }, $class;
}

sub work {
    my ($self, $task) = @_;

    if ($task->type eq 'configure') {

    }
    if ($task->type eq 'build') {
    }

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

sub configure {
    my ($self, $task) = @_;

    my $guard = File::pushd::pushd $task->directory;
    my $build_type = -f 'Build.PL' ? 'mb' : 'mm';

    local $self->{logger}{context} = $task->disturl;
    my $ok = $self->_execute($^X, $build_type eq 'mb' ? 'Build.PL' : 'Makefile.PL');
    if (!$ok || !-f 'MYMETA.json') {
        return { err => 'failed to configure' };
    }

    my $mymeta = CPAN::Meta->load_file('MYMETA.json');
    my $requiremnt = $self->extract_requiremnt($mymeta, ['build', 'runtime']);
}

sub build {
    my ($self, $task) = @_;
    my $guard = File::pushd::pushd $task->directory;
    local $self->{logger}{context} = $task->disturl;
    my $ok = $self->_execute($task->build_type eq 'mb' ? ('./Build', 'build') : ('make', 'build'));
    $ok;
}

sub install {
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

sub _execute {
    my ($self, @cmd) = @_;
    $self->{logger}->log("Executing @cmd");
    my $out;
    IPC::Run3::run3 \@cmd, undef, \$out, \$out;
    my $exit = $?;
    $self->{logger}->log($out);
    $exit == 0;
}

sub _examine {
    my ($self, $directory) = @_;

    my $meta;
    if (my ($file) = grep -f, map File::Spec->catfile($directory, $_), qw(META.json META.yml)) {
        $meta = eval { CPAN::Meta->load_file($file) };
    }
    die if !$meta;
    my $requirement = $self->extract_requiremnt($meta, ['configure']);

    my $provides = Parse::LocalDistribution->new({ALLOW_DEV_VERSION => 1})->parse($directory);
    for my $v (values %$provides) {
        delete $v->{filemtime};
        delete $v->{infile};
        delete $v->{version} if $v->{version} eq 'undef';
    }

    ($meta, $requirement, $provides);
}

1;
