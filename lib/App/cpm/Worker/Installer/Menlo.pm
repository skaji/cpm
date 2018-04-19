package App::cpm::Worker::Installer::Menlo;
use strict;
use warnings;
use parent 'Menlo::CLI::Compat';

use App::cpm::Logger::File;
use Menlo::Builder::Static;

our $VERSION = '0.963';

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
        $self->{logger}->log("Executing $cmd");
        !system $cmd;
    } else {
        $self->run_exec($cmd);
    }
}

sub run_exec {
    my($self, $cmd) = @_;

    $self->{logger}->log("Executing " . (ref $cmd ? "@$cmd" : $cmd));
    my $status = App::cpm::Worker::Installer::Menlo::Command
        ->new(ref $cmd ? @$cmd : $cmd)
        ->redirect(1)
        ->on(stdout => sub { $self->log(@_) })
        ->exec;
    return $status == 0;
}

sub run_timeout {
    my($self, $cmd, $timeout) = @_;

    return $self->run_command($cmd) if ref($cmd) eq 'CODE' || WIN32 || $self->{verbose} || !$timeout;

    $self->{logger}->log("Executing " . (ref $cmd ? "@$cmd" : $cmd));
    my $status = App::cpm::Worker::Installer::Menlo::Command
        ->new(ref $cmd ? @$cmd : $cmd)
        ->redirect(1)
        ->on(stdout => sub { $self->log(@_) })
        ->timeout($timeout)
        ->on(timeout => sub { $self->diag_fail("Timed out (> ${timeout}s).") })
        ->exec;

    # TODO return flag for timeout or not
    # and if timeout, do not retry run_timeout()
    return $status == 0;
}

{
    package
        App::cpm::Worker::Installer::Menlo::LineBuffer;
    sub new {
        my $class = shift;
        bless { buffer => "" }, $class;
    }
    sub append {
        my ($self, $buffer) = @_;
        $self->{buffer} .= $buffer;
        $self;
    }
    sub get {
        my ($self, $drain) = @_;
        if ($drain) {
            if (length $self->{buffer}) {
                my @line = $self->get;
                if (length $self->{buffer}) {
                    push @line, $self->{buffer};
                    $self->{buffer} = "";
                }
                return @line;
            } else {
                return;
            }
        }
        my @line;
        while ($self->{buffer} =~ s/\A(.*?\n)//sm) {
            push @line, $1;
        }
        return @line;
    }
}

{
    package
        App::cpm::Worker::Installer::Menlo::Command;
    use IO::Select;
    use POSIX ();
    use Time::HiRes ();
    use Config ();

    sub new {
        my ($class, @command) = @_;
        bless {
            buffer   => {},
            command  => \@command,
            on       => {},
            redirect => undef,
            tick     => 0.05,
        }, $class;
    }
    sub on {
        my ($self, $type, $sub) = @_;
        my %valid = map { $_ => 1 } qw(stdout stderr timeout);
        if (!$valid{$type}) {
            die "unknown type '$type' passes to on() method";
        }
        $self->{on}{$type} = $sub;
        $self;
    }
    sub timeout {
        my ($self, $sec) = @_;
        $self->{timeout} = $sec;
        $self;
    }
    sub redirect {
        my ($self, $bool) = @_;
        $self->{redirect} = $bool;
        $self;
    }
    sub tick {
        my ($self, $tick) = @_;
        $self->{tick} = $tick;
        $self;
    }
    sub exec {
        my $self = shift;
        pipe my $stdout_read, my $stdout_write;
        my ($stderr_read, $stderr_write);
        pipe $stderr_read, $stderr_write unless $self->{redirect};
        my $pid = fork;
        die "fork: $!" unless defined $pid;
        if ($pid == 0) {
            close $_ for grep $_, $stdout_read, $stderr_read;
            open STDOUT, ">&", $stdout_write;
            if ($self->{redirect}) {
                open STDERR, ">&", \*STDOUT;
            } else {
                open STDERR, ">&", $stderr_write;
            }
            if ($Config::Config{d_setpgrp}) {
                POSIX::setpgid(0, 0) or die "setpgid: $!";
            }
            exec @{$self->{command}};
            exit 127;
        }
        close $_ for grep $_, $stdout_write, $stderr_write;

        my $INT; local $SIG{INT} = sub { $INT++ };
        my $is_timeout;
        my $timeout_at = $self->{timeout} ? Time::HiRes::time() + $self->{timeout} : undef;
        my $select = IO::Select->new(grep $_, $stdout_read, $stderr_read);
        while (1) {
            last if $INT;
            last if $select->count == 0;
            for my $ready ($select->can_read($self->{tick})) {
                my $type = $ready == $stdout_read ? "stdout" : "stderr";
                my $len = sysread $ready, my $buf, 64*1024;
                if (!defined $len) {
                    warn "sysread pipe failed: $!";
                    last;
                } elsif ($len == 0) {
                    $select->remove($ready);
                    close $ready;
                } else {
                    my $buffer = $self->{buffer}{$type}
                             ||= App::cpm::Worker::Installer::Menlo::LineBuffer->new;
                    $buffer->append($buf);
                    my @line = $buffer->get;
                    next unless @line;
                    my $sub = $self->{on}{$type} ||= sub {};
                    $sub->(@line);
                }
            }
            if ($timeout_at) {
                my $now = Time::HiRes::time();
                if ($now > $timeout_at) {
                    $is_timeout++;
                    last;
                }
            }
        }
        for my $type (qw(stdout stderr)) {
            my $buffer = $self->{buffer}{$type} or next;
            my @line = $buffer->get(1) or next;
            my $sub = $self->{on}{$type} || sub {};
            $sub->(@line);
        }
        close $_ for $select->handles;
        if ($INT) {
            my $target = $Config::Config{d_setpgrp} ? -$pid : $pid;
            kill INT => $target;
        }
        if ($is_timeout) {
            if (my $on_timeout = $self->{on}{timeout}) {
                $on_timeout->($pid);
            }
            my $target = $Config::Config{d_setpgrp} ? -$pid : $pid;
            kill TERM => $target;
        }
        waitpid $pid, 0;
        return $?;
    }
}

1;
