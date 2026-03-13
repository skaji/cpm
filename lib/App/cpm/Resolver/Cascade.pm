package App::cpm::Resolver::Cascade;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

sub new ($class, $ctx) {
    bless { backends => [] }, $class;
}

sub add ($self, $resolver) {
    push $self->{backends}->@*, $resolver;
    $self;
}

sub resolve ($self, $ctx, $task) {
    # here task = { package => "Plack", version_range => ">= 1.000, < 1.0030" }

    my @error;
    for my $backend ($self->{backends}->@*) {
        my $result = $backend->resolve($ctx, $task);
        next unless $result;

        my $klass = ref $backend;
        $klass = $1 if $klass =~ /^App::cpm::Resolver::(.*)$/;
        if (my $error = $result->{error}) {
            push @error, "$klass, $error";
        } else {
            $result->{from} = $klass;
            return $result;
        }
    }
    push @error, "no resolver backends" if !@error;
    return { error => join("\n", @error) };
}

1;
