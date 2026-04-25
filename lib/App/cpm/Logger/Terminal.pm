package App::cpm::Logger::Terminal;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

package App::cpm::Logger::Terminal::_Lines {
    use v5.24;
    use warnings;
    use experimental qw(lexical_subs signatures);

    my %ING = (
        resolve   => "resolving",
        fetch     => "fetching",
        configure => "configuring",
        build     => "building",
        test      => "testing",
        install   => "installing",
    );

    sub new ($class, $pids, $progress, $use_color) {
        my $num = keys $pids->%*;
        bless {
            pids => $pids,
            progress => $progress,
            num => $num,
            use_color => $use_color,
            _lines => [],
        }, $class;
    }

    sub set_worker ($self, $pid, $task = undef) {
        my ($progress, $ing, $name) = $task
            ? ($self->{progress}, $ING{$task->type} || $task->type, $task->distvname)
            : (" ", "idle", "");
        $ing = sprintf "%-11s", $ing;
        $ing = "\e[1;30m$ing\e[m" if $self->{use_color};
        $self->{_lines}[ $self->{pids}{$pid} ] = sprintf "%s %-11s %s\n",
            $progress, $ing, $name;
    }

    sub set_summary ($self, $done, $all) {
        $self->{_lines}[ $self->{num} ] = sprintf "--- %d/%d ---\n", $done, $all;
    }

    sub lines ($self) {
        $self->{_lines}->@*;
    }
}

sub new ($class, @pid) {
    my %pid = map { ($pid[$_], $_) } 0 .. $#pid;
    bless {
        first => 1,
        pids => \%pid,
        lines => 1 + (keys %pid),
        fh => \*STDERR,
        progress_index => 0,
        use_color => 1,
    }, $class;
}

my @PROGRESS = qw(\\ | / -);

sub use_color ($self, $value = undef) {
    $self->{use_color} = $value ? 1 : 0 if defined $value;
    $self->{use_color};
}

sub progress ($self) {
    $self->{progress_index} = ($self->{progress_index} + 1) % @PROGRESS;
    $PROGRESS[ $self->{progress_index} ];
}

sub new_lines ($self) {
    App::cpm::Logger::Terminal::_Lines->new($self->{pids}, $self->progress, $self->{use_color});
}

sub clear ($self) {
    return if $self->{first};
    $self->{fh}->print(("\e[1A\e[K") x $self->{lines});
}

sub write ($self, $lines) {
    $self->clear;
    $self->{first} = 0;
    $self->{fh}->print($lines->lines);
}

sub finalize ($self) {
    $self->clear;
    $self->{first} = 1;
}

1;
