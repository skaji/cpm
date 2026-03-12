package App::cpm::Context;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::HTTP;
use App::cpm::Installer::Unpacker;
use App::cpm::Logger::File;
use Command::Runner;
use Config;
use File::Which ();

sub new ($class, %argv) {
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

sub log ($self, @msg) {
    $self->{logger}->log(@msg);
}

sub run_command ($self, $cmd, $timeout = 0) {
    my $str = ref $cmd eq 'CODE' ? '' : ref $cmd eq 'ARRAY' ? "@$cmd" : $cmd;
    $self->log("Executing $str") if $str;
    my $runner = Command::Runner->new(
        command => $cmd,
        keep => 0,
        redirect => 1,
        timeout => $timeout,
        stdout => sub (@msg) { $self->log(@msg) },
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
