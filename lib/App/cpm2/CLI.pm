package App::cpm2::CLI;
use strict;
use warnings;

use App::cpm2::Master;
use App::cpm2::Worker;
use Parallel::Pipes;
use List::Util ();

sub new {
    my $class = shift;
    bless {
    }, $class;
}

sub run {
    my ($self, @package) = @_;

    my $master = App::cpm2::Master->new;
    my $worker = App::cpm2::Worker->new;

    for my $package (@package) {
        $master->add_task(type => 'resolve', package => $package);
    }
    $self->install($master, $worker);
}

sub install {
    my ($self, $master, $worker) = @_;

    my $pipes = Parallel::Pipes->new(5, sub {
        my $task = shift;
        my $result = $worker->work($task);
        return $result;
    });

    my $get_task; $get_task = sub {
        my $master = shift;
        if (my @task = $master->get_task) {
            return @task;
        }
        if (my @written = $pipes->is_written) {
            my @ready = $pipes->is_ready(@written);
            $master->register_result($_->read) for @ready;
            return $master->$get_task;
        } else {
            return;
        }
    };

    while (my @task = $master->$get_task) {
        my @ready = $pipes->is_ready;
        $master->register_result($_->read) for grep $_->is_written, @ready;
        my $min = List::Util::min($#task, $#ready);
        for my $i (0..$min) {
            $task[$i]->running(1);
            $ready[$i]->write($task[$i]);
        }
    }
    $pipes->close;
}

1;
