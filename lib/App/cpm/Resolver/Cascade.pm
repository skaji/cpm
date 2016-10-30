package App::cpm::Resolver::Cascade;
use strict;
use warnings;
our $VERSION = '0.210';

sub new {
    my $class = shift;
    bless { backends => [] }, $class;
}

sub add {
    my ($self, $resolver) = @_;
    push @{ $self->{backends} }, $resolver;
    $self;
}

sub resolve {
    my ($self, $job) = @_;
    # here job = { package => "Plack", version => ">= 1.000, < 1.0030" }

    for my $backend (@{ $self->{backends} }) {
        my $result = $backend->resolve($job);
        if ($result) {
            my $klass = ref $backend;
            if ($klass =~ /^App::cpm::Resolver::(.*)$/) {
                $result->{from} = $1;
            } else {
                $result->{from} = $klass;
            }
            return $result;
        }
    }
    return;
}

1;
