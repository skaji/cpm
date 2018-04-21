package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;
use parent 'Menlo::CLI::Compat';

use App::cpm::Logger::File;
use Menlo::Builder::Static;
use Command::Runner;
use App::cpm::HTTP;

our $VERSION = '0.967';

use constant WIN32 => Menlo::CLI::Compat::WIN32();

sub new {
    my ($class, %option) = @_;
    $option{log} ||= $option{logger}->file;
    my $self = $class->SUPER::new(%option);
    $self->init_tools;
    $self->{http} = App::cpm::HTTP->new; # overwrite
    $self;
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

    $cmd = Menlo::Util::shell_quote(@$cmd) if WIN32 and ref $cmd eq 'ARRAY';

    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->{logger}->log("Executing $str") if $str;

    my $runner = Command::Runner->new(
        command => $cmd,
        redirect => 1,
        timeout => $timeout,
        on => { stdout => sub { $self->log(@_) } },
    );
    my ($status, $is_timeout) = $runner->run;
    if ($is_timeout) {
        $self->diag_fail("Timed out (> ${timeout}s).");
        return;
    }
    ref $cmd eq 'CODE' ? $status : $status == 0;
}

1;
