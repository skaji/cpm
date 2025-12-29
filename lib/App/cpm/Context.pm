package App::cpm::Context;
use strict;
use warnings;

use App::cpm::HTTP;
use App::cpm::Installer::Unpacker;
use App::cpm::Logger::File;
use Command::Runner;
use Config;
use File::Which ();

sub new {
    my ($class, %argv) = @_;
    my $logger = App::cpm::Logger::File->new($argv{log_file});
    my ($http, $http_description) = App::cpm::HTTP->create;
    my $unpacker = App::cpm::Installer::Unpacker->new;
    my $make = File::Which::which($Config{make});
    bless {
        logger => $logger,
        make => $make,
        perl => $^X,
        http => $http,
        http_description => $http_description,
        unpacker => $unpacker,
    }, $class;
}

sub log {
    my ($self, @msg) = @_;
    $self->{logger}->log(@msg);
}

sub run_command {
    my ($self, $cmd, $timeout) = @_;
    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->log("Executing $str") if $str;
    my $runner = Command::Runner->new(
        command => $cmd,
        keep => 0,
        redirect => 1,
        timeout => $timeout,
        stdout => sub { $self->log(@_) },
    );
    my $res = $runner->run;
    if ($res->{timeout}) {
        $self->log("Timed out (> ${timeout}s).");
        return;
    }
    my $result = $res->{result};
    ref $cmd eq 'CODE' ? $result : $result == 0;
}

1;
