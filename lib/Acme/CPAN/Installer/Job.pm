package Acme::CPAN::Installer::Job;
use strict;
use warnings;
use utf8;

sub new {
    my ($class, %option) = @_;
    my $self = bless {result => undef, %option}, $class;
    $self->{uid} = $self->_uid;
    $self;
}

sub uid { shift->{uid} }

sub _uid {
    my $self = shift;
    my $type = $self->type;
    if ($type eq "install") {
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

sub result {
    my $self = shift;
    $self->{result};
}

sub is_success {
    my $self = shift;
    my $result = $self->result or return;
    $result->{ok};
}

sub equals {
    my ($self, $that) = @_;
    $self->uid eq $that->uid;
}

1;
