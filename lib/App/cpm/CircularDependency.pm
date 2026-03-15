package App::cpm::CircularDependency;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use List::Util 'uniqstr';

package App::cpm::CircularDependency::_OrderedSet {
    sub new ($class) {
        bless { index => 0, hash => +{} }, $class;
    }
    sub add ($self, $name) {
        $self->{hash}{$name} = $self->{index}++;
    }
    sub exists ($self, $name) {
        exists $self->{hash}{$name};
    }
    sub values ($self) {
        sort { $self->{hash}{$a} <=> $self->{hash}{$b} } keys $self->{hash}->%*;
    }
    sub clone ($self) {
        my $new = (ref $self)->new;
        $new->add($_) for $self->values;
        $new;
    }
}

sub new ($class) {
    bless { _tmp => {} }, $class;
}

sub add ($self, $distfile, $provides, $requirements) {
    $self->{_tmp}{$distfile} = +{
        provides => [ map $_->{package}, $provides->@* ],
        requirements => [ map $_->{package}, $requirements->@* ],
    };
}

sub finalize ($self) {
    for my $distfile (sort keys $self->{_tmp}->%*) {
        $self->{$distfile} = [
            uniqstr map $self->_find($_), $self->{_tmp}{$distfile}{requirements}->@*
        ];
    }
    delete $self->{_tmp};
    return;
}

sub _find ($self, $package) {
    for my $distfile (sort keys $self->{_tmp}->%*) {
        if (grep { $_ eq $package } $self->{_tmp}{$distfile}{provides}->@*) {
            return $distfile;
        }
    }
    return;
}

sub detect ($self) {
    my %result;
    for my $distfile (sort keys $self->%*) {
        my $seen = App::cpm::CircularDependency::_OrderedSet->new;
        $seen->add($distfile);
        if (my $detected = $self->_detect($distfile, $seen)) {
            $result{$distfile} = $detected;
        }
    }
    return \%result;
}

sub _detect ($self, $distfile, $seen) {
    for my $req ($self->{$distfile}->@*) {
        if ($seen->exists($req)) {
            return [$seen->values, $req];
        }

        my $clone = $seen->clone;
        $clone->add($req);
        if (my $detected = $self->_detect($req, $clone)) {
            return $detected;
        }
    }
    return;
}

1;
