package Acme::CPAN::Installer::Job;
use strict;
use warnings;
use utf8;

sub new {
    my ($class, %option) = @_;
    my $self = bless {%option}, $class;
    $self->{uid} = $self->_uid;
    $self;
}

sub uid { shift->{uid} }

sub _uid {
    my $self = shift;
    my $type = $self->type;
    if (grep { $type eq $_ } qw(fetch configure install)) {
        "$type " . $self->{distfile};
    } elsif ($type eq "resolve") {
        "$type " . $self->{package};
    } else {
        die "unknown type: " . ($type || "(undef)");
    }
}

sub type {
    my $self = shift;
    $self->{type};
}

sub in_charge {
    my $self = shift;
    @_ ? $self->{in_charge} = shift : $self->{in_charge};
}

sub is_success {
    my $self = shift;
    $self->{ok};
}

sub equals {
    my ($self, $that) = @_;
    $self->uid eq $that->uid;
}

1;
