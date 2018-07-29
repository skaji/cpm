package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;

use parent 'Menlo::CLI::Compat';

use App::cpm::HTTP;
use App::cpm::Util 'WIN32';
use App::cpm::Logger::File;
use Command::Runner;
use Menlo::Builder::Static;

sub new {
    my ($class, %option) = @_;
    $option{log} ||= $option{logger}->file;
    my $self = $class->SUPER::new(%option);
    $self->init_tools;
    $self;
}

sub configure_http {
    my $self = shift;
    my ($http, $desc) = App::cpm::HTTP->create;
    $self->{logger}->log("You have $desc");
    $http;
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

    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->{logger}->log("Executing $str") if $str;

    my $runner = Command::Runner->new(
        command => $cmd,
        keep => 0,
        redirect => 1,
        timeout => $timeout,
        stdout => sub { $self->log(@_) },
    );
    my $res = $runner->run;
    if ($res->{timeout}) {
        $self->diag_fail("Timed out (> ${timeout}s).");
        return;
    }
    my $result = $res->{result};
    ref $cmd eq 'CODE' ? $result : $result == 0;
}

1;
