package App::cpm2::Worker;
use strict;
use warnings;

use App::cpm2::Installer;
use App::cpm2::Resolver;

sub new {
    my $class = shift;
    bless {
        installer => App::cpm2::Installer->new,
        resolver  => App::cpm2::Resolver->new,
    }, $class;
}

sub work {
    my ($self, $task) = @_;

    my $type = $task->{type};

    if ($type eq "resolve") {
        my ($res, $err) = $self->{resolver}->resolve($task->{package}, $task->{version});
    }
    if ($type eq "fetch") {
        my ($file, $err) = $self->{fetcher}->fetch($task->{disturl});
    }

    return $self->{installer}->work($task);
}

1;
