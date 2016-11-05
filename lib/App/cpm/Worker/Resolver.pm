package App::cpm::Worker::Resolver;
use strict;
use warnings;
our $VERSION = '0.213';

sub new {
    my ($class, %option) = @_;
    bless { impl => $option{impl} }, $class;
}

sub work {
    my ($self, $job) = @_;
    if (my $result = $self->{impl}->resolve($job)) {
        $result->{ok} = 1;
        $result->{uri} = [$result->{uri}] unless ref $result->{uri};
        return $result;
    } else {
        return { ok => 0 };
    }
}

1;
