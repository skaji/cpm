package App::cpm::Resolver::Multiplexer;
use strict;
use warnings;

sub new {
    my $class = shift;
    bless { backends => [] }, $class;
}

sub append {
    my ($self, $resolver) = @_;
    if ( ! eval { $resolver->can("resolve") } ) {
        my $class = ref $self;
        die "$class\->append only accepts objects that have resolve method";
    }
    push @{ $self->{backends} }, $resolver;
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
