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
    my $logger = $argv{logger} || App::cpm::Logger::File->new;
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

1;
