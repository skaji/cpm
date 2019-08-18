package App::cpm2::Task;
use strict;
use warnings;

sub new {
    my ($class, %argv) = @_;
    bless { %argv }, $class;
}

sub id {
    my $self = shift;

    sprintf "%s %s",
        $self->{type},
        $self->{type} eq "resolve" ? $self->{package} : $self->{disturl};
}

sub running {
    my $self = shift;
    $self->{_running} = 1 if @_ && $_[0];
    $self->{_running};
}

1;
