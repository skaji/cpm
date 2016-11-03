package App::cpm::Distribution;
use strict;
use warnings;
use App::cpm::version;
use App::cpm::Logger;
use CPAN::DistnameInfo;
our $VERSION = '0.212';

use constant STATE_REGISTERED => 0b00001;
use constant STATE_RESOLVED   => 0b00010; # default
use constant STATE_FETCHED    => 0b00100;
use constant STATE_CONFIGURED => 0b01000;
use constant STATE_INSTALLED  => 0b10000;

sub new {
    my ($class, %option) = @_;
    my $uri = delete $option{uri};
    $uri = [$uri] unless ref $uri;
    my $distfile = delete $option{distfile};
    my $source = delete $option{source} || "cpan";
    my $provides = delete $option{provides} || [];
    bless {%option, provides => $provides, uri => $uri, distfile => $distfile, source => $source, _state => STATE_RESOLVED}, $class;
}

for my $attr (qw(
    source
    configure_requirements
    directory
    distdata
    meta
    uri
    provides
    requirements
    ref
)) {
    no strict 'refs';
    *$attr = sub {
        my $self = shift;
        $self->{$attr} = shift if @_;
        $self->{$attr};
    };
}
sub distfile {
    my $self = shift;
    $self->{distfile} = shift if @_;
    $self->{distfile} || $self->{uri}[0];
}

sub distvname {
    my $self = shift;
    $self->{distvname} ||= do {
        CPAN::DistnameInfo->new($self->{distfile})->distvname || $self->distfile;
    };
}

sub overwrite_provide {
    my ($self, $provide) = @_;
    my $overwrited;
    for my $exist (@{$self->{provides}}) {
        if ($exist->{package} eq $provide->{package}) {
            $exist = $provide;
            $overwrited++;
        }
    }
    if (!$overwrited) {
        push @{$self->{provides}}, $provide;
    }
    return 1;
}

sub registered {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} |= STATE_REGISTERED;
    }
    $self->{_state} & STATE_REGISTERED;
}

sub resolved {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_RESOLVED;
    }
    $self->{_state} & STATE_RESOLVED;
}

sub fetched {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_FETCHED;
    }
    $self->{_state} & STATE_FETCHED;
}

sub configured {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_CONFIGURED
    }
    $self->{_state} & STATE_CONFIGURED;
}

sub installed {
    my $self = shift;
    if (@_ && $_[0]) {
        $self->{_state} = STATE_INSTALLED;
    }
    $self->{_state} & STATE_INSTALLED;
}

sub providing {
    my ($self, $package, $version) = @_;
    for my $provide (@{$self->provides}) {
        if ($provide->{package} eq $package) {
            if (!$version or App::cpm::version->parse($provide->{version})->satisfy($version)) {
                return 1;
            } else {
                my $message = sprintf "%s provides %s (%s), but needs %s\n",
                    $self->distfile, $package, $provide->{version}, $version;
                App::cpm::Logger->log(result => "WARN", message => $message);
                last;
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
