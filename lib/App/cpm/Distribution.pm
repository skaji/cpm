package App::cpm::Distribution;
use strict;
use warnings;
use version;

sub new {
    my ($class, %option) = @_;
    bless {_state => 0, %option}, $class;
}

for my $attr (qw(
    configure_requirements
    directory
    distdata
    distfile
    meta
    provides
    requirements
)) {
    no strict 'refs';
    *$attr = sub {
        my $self = shift;
        $self->{$attr} = shift if @_;
        $self->{$attr};
    };
}

sub append_provide {
    my ($self, $provide) = @_;
    return if $self->providing($provide->{package});
    push @{$self->{provides}}, $provide;
    return 1;
}

use constant STATE_RESOLVED   => 0; # default
use constant STATE_FETCHED    => 1;
use constant STATE_CONFIGURED => 2;
use constant STATE_INSTALLED  => 3;

sub resolved {
    my $self = shift;
    $self->{_state} == STATE_RESOLVED;
}

sub fetched {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_FETCHED;
    }
    $self->{_state} == STATE_FETCHED;
}

sub configured {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_CONFIGURED
    }
    $self->{_state} == STATE_CONFIGURED;
}

sub installed {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_INSTALLED;
    }
    $self->{_state} == STATE_INSTALLED;
}

sub providing {
    my ($self, $package, $version) = @_;
    for my $provide (@{$self->provides}) {
        if ($provide->{package} eq $package) {
            return 1 unless $version;
            if (version->parse($version) <= version->parse($provide->{version})) {
                return 1;
            } else {
                warn sprintf "-> %s provides %s (%s), but needs %s\n",
                    $self->distfile, $package, $provide->{version}, $version;
            }
        }
    }
    return;
}

sub equals {
    my ($self, $that) = @_;
    $self->distfile && $that->distfile and $self->distfile eq $that->distfile;
}

1;
