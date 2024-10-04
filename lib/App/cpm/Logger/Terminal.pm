package App::cpm::Logger::Terminal;
use strict;
use warnings;

{
    package App::cpm::Logger::Terminal::Lines;
    sub new {
        my ($class, $pids, $progress) = @_;
        my $num = keys %$pids;
        bless {
            pids => $pids,
            progress => $progress,
            num => $num,
            worker_prefix => $num < 10 ? "worker%d" : "worker%-2d",
            _lines => [],
        }, $class;
    }
    my %_ing = (install => "installing", resolve => "resolving", fetch => "fetching", configure => "configuring");
    sub set_worker {
        my ($self, $pid, $task) = @_;
        my $i = $self->{pids}{$pid};
        my ($progress, $ing, $name) = $task ?
            ($self->{progress}, $_ing{$task->type}, $task->distvname) : (" ", "idle", "");
        $self->{_lines}[$i] = sprintf "$self->{worker_prefix} %s \e[1;30m%-11s\e[m %s\n",
            $i+1, $progress, $ing, $name;
    }
    sub set_summary {
        my ($self, $all, $num) = @_;
        $self->{_lines}[$self->{num}] = "--- $num/$all ---\n";
    }
    sub lines {
        my $self = shift;
        @{$self->{_lines}};
    }
}

use IO::Handle;

sub new {
    my ($class, @pid) = @_;
    my %pid = map { ($pid[$_], $_) } 0 .. $#pid;
    bless {
        first => 1,
        pids => \%pid,
        lines => 1 + (keys %pid),
        fh => \*STDERR,
        _progress_index => 0,
    }, $class;
}

my @_progress = qw(\\ | / -);
sub progress {
    my $self = shift;
    $self->{_progress_index} = ($self->{_progress_index}+1) % 4;
    $_progress[$self->{_progress_index}];
}

sub new_lines {
    my $self = shift;
    App::cpm::Logger::Terminal::Lines->new($self->{pids}, $self->progress);
}

sub clear {
    my $self = shift;
    $self->{fh}->print( ("\e[1A\e[K") x $self->{lines} );
}

sub write {
    my ($self, $lines) = @_;
    if ($self->{first}) {
        $self->{first} = undef;
    } else {
        $self->clear;
    }
    $self->{fh}->print($lines->lines);
}

1;
