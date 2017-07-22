package App::cpm::CircularDependency;
use strict;
use warnings;
our $VERSION = '0.912';

{
    package
        App::cpm::CircularDependency::OrderedSet;
    sub new {
        my $class = shift;
        bless { index => 0, hash => +{} }, $class;
    }
    sub add {
        my ($self, $name) = @_;
        $self->{hash}{$name} = $self->{index}++;
    }
    sub exists {
        my ($self, $name) = @_;
        exists $self->{hash}{$name};
    }
    sub values {
        my $self = shift;
        sort { $self->{hash}{$a} <=> $self->{hash}{$b} } keys %{$self->{hash}};
    }
    sub after {
        my ($self, $name) = @_;
        my @value = $self->values;
        while (my $value = shift @value) {
            if ($value eq $name) {
                my $new = (ref $self)->new;
                $new->add($value);
                $new->add($_) for @value;
                return $new;
            }
        }
        return;
    }
}

sub new {
    my $class = shift;
    bless {}, $class;
}

sub add {
    my ($self, $name, $provides, $requirements) = @_;
    $self->{$name} = +{
        provides => [ map $_->{package}, @$provides ],
        requirements => [ map $_->{package}, @$requirements ],
    };
}

sub detect {
    my $self = shift;

    my %ret;
    for my $name (sort keys %$self) {
        my $set = App::cpm::CircularDependency::OrderedSet->new;
        if (my $ret =  $self->_detect($name, $set)) {
            $ret{$name} = [ $ret->values ];
        }
    }
    return %ret ? \%ret : undef;
}

sub _find {
    my ($self, $package) = @_;
    my $found;
    for my $name (sort keys %$self) {
        if (grep { $_ eq $package } @{$self->{$name}{provides}}) {
            $found = $name, last;
        }
    }
    return $found;
}

sub _detect {
    my ($self, $name, $set) = @_;
    return $set->after($name) if $set->exists($name);

    $set->add($name);

    for my $requirement (grep $_, map $self->_find($_), @{ $self->{$name}{requirements} }) {
        my $new_set = $self->_detect($requirement, $set);
        return $new_set if $new_set;
    }
    return;
}

1;
