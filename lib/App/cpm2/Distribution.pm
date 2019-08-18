package App::cpm2::Distribution;
use strict;
use warnings;

use constant STATE_REGISTERD  => 0b1;

use constant STATE_FAILED     => 0b10;

use constant STATE_RESOLVED   => 0b1000;
use constant STATE_FETCHED    => 0b10000;
use constant STATE_CONFIGURED => 0b100000;
use constant STATE_BUILT      => 0b1000000;
use constant STATE_READY      => 0b10000000;


sub new {
    my ($class, %argv) = @_;
    bless { %argv, _state => STATE_RESOLVED }, $class;
}

sub registerd {
    my $self = shift;
    $self->{_state} |= STATE_REGISTERD if @_ && $_[0];
    $self->{_state} & STATE_REGISTERD;
}

sub failed {
    my $self = shift;
    $self->{_state} = STATE_FAILED if @_ && $_[0];
    $self->{_state} & STATE_FAILED;
}

sub resolved {
    my $self = shift;
    $self->{_state} = STATE_RESOLVED if @_ && $_[0];
    $self->{_state} & STATE_RESOLVED;
}

sub fetched {
    my $self = shift;
    $self->{_state} = STATE_FETCHED if @_ && $_[0];
    $self->{_state} & STATE_FETCHED;
}

sub configured {
    my $self = shift;
    $self->{_state} = STATE_CONFIGURED if @_ && $_[0];
    $self->{_state} & STATE_CONFIGURED;
}

sub built {
    my $self = shift;
    $self->{_state} = STATE_BUILT if @_ && $_[0];
    $self->{_state} & STATE_BUILT;
}

sub ready_to_install {
    my $self = shift;
    $self->{_state} = STATE_READY if @_ && $_[0];
    $self->{_state} & STATE_READY;
}

sub requirement {
    my $self = shift;

    if (@_ == 1) {
        my %merge;
        for my $phase (@{$_[0]}) {
            for my $req (@{$self->{requirement}{$phase}}) {
                if (exists $merge{$req->{package}}) {
                    my $old = $merge{$req->{package}};
                    my $new = $req->{version_range};
                    $merge{$req->{package}} = App::cpm2::version::merge($old, $new);
                } else {
                    $merge{$req->{package}} = $req->{version_range};
                }
            }
        }
        return [ map { +{ package => $_, version_range => $merge{$_} } } keys %merge ];
    }

    my %requirement = @_;
    for my $phase (keys %requirement) {
        $self->{requirement}{$phase} = $requirement{$phase};
    }
}

sub dependency {
    my $self = shift;

    if (@_ == 1) {
        my %merge;
        for my $phase (@{$_[0]}) {
            for my $dependency (@{$self->{dependency}{$phase}}) {
                $merge{$dependency}++;
            }
        }
        return [ keys %merge ];
    }

    my %dependency = @_;
    for my $phase (keys %dependency) {
        $self->{dependency}{$phase} = $dependency{$phase};
    }
}

sub providing {
    my ($self, $requirement) = @_;

    for my $package (sort keys %{$self->{provides}}) {
        if ($package eq $requirement->{package}) {
            my $have = $self->{provides}{$package};
            my $want = $requirement->{version_range};
            return 1; # XXX
        }
    }
    return;
}

sub lib {
}

sub bin {
}

1;
