package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;
use parent 'Menlo::CLI::Compat';

use App::cpm::Logger::File;
use Menlo::Builder::Static;

our $VERSION = '0.298';

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
    my($self, $cmd) = @_;

    # TODO move to a more appropriate runner method
    if (ref $cmd eq 'CODE') {
        if ($self->{verbose}) {
            return $cmd->();
        } else {
            require Capture::Tiny;
            open my $fh, "+>", undef;
            my $ret;
            Capture::Tiny::capture(sub { $ret = $cmd->() }, stdout => $fh, stderr => $fh);
            seek $fh, 0, 0;
            $self->{logger}->log_with_fh($fh);
            return $ret;
        }
    }

    if (WIN32) {
        # TODO
        $cmd = Menlo::Util::shell_quote(@$cmd) if ref $cmd eq 'ARRAY';
        unless ($self->{verbose}) {
            $cmd .= " >> " . Menlo::Util::shell_quote($self->{log}) . " 2>&1";
        }
        !system $cmd;
    } else {
        $self->run_exec($cmd);
    }
}

sub run_exec {
    my($self, $cmd) = @_;

    my $pid = open my $fh, "-|";
    if ($pid == 0) {
        open STDERR, ">&", \*STDOUT;
        if (ref $cmd eq 'ARRAY') {
            exec {$cmd->[0]} @$cmd;
        } else {
            exec $cmd;
        }
        exit 255;
    } else {
        $self->{logger}->log_with_fh($fh);
        close $fh;
        return !$?;
    }
}

sub run_timeout {
    my($self, $cmd, $timeout) = @_;

    return $self->run_command($cmd) if ref($cmd) eq 'CODE' || WIN32 || $self->{verbose} || !$timeout;

    my $pid = fork;
    if ($pid) {
        eval {
            local $SIG{ALRM} = sub { die "alarm\n" };
            alarm $timeout;
            waitpid $pid, 0;
            alarm 0;
        };
        if ($@ && $@ eq "alarm\n") {
            $self->diag_fail("Timed out (> ${timeout}s). Use --verbose to retry.");
            local $SIG{TERM} = 'IGNORE';
            kill TERM => 0;
            waitpid $pid, 0;
            return;
        }
        return !$?;
    } elsif ($pid == 0) {
        my $ret = $self->run_exec($cmd);
        exit($ret ? 0 : 1);
    } else {
        $self->chat("! fork failed: falling back to system()\n");
        $self->run_command($cmd);
    }
}

1;
