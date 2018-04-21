package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;
use parent 'Menlo::CLI::Compat';

use App::cpm::Logger::File;
use Menlo::Builder::Static;
use Command::Runner;

our $VERSION = '0.969';

use constant WIN32 => Menlo::CLI::Compat::WIN32();

sub new {
    my ($class, %option) = @_;
    $option{log} ||= $option{logger}->file;
    my $self = $class->SUPER::new(%option);
    $self->init_tools;
    $self->_set_http_agent;
    $self;
}

sub _set_http_agent {
    my $self = shift;
    my $agent = "App::cpm/$VERSION";
    my $http = $self->{http};
    my $klass = ref $http;
    if ($klass =~ /HTTP::Tinyish::(Curl|Wget)/) {
        $http->{agent} = $agent;
    } elsif ($klass eq 'HTTP::Tinyish::LWP') {
        $http->{ua}->agent($agent);
    } elsif ($klass eq 'HTTP::Tinyish::HTTPTiny') {
        $http->{tiny}->agent($agent);
    } else {
        die "Unknown http class: $klass\n";
    }
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
    my $res = $runner->run;
    if ($res->{timeout}) {
        $self->diag_fail("Timed out (> ${timeout}s).");
        return;
    }
    my $result = $res->{result};
    ref $cmd eq 'CODE' ? $result : $result == 0;
}

1;
