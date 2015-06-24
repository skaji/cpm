package Acme::CPAN::Installer::Distribution;
use strict;
use warnings;
use Module::CoreList;

sub new {
    my ($class, %option) = @_;
    bless {%option}, $class;
}

sub provides {
    shift->{provides} || [];
}

sub requirements {
    shift->{requirements} || [];
}

sub distfile {
    shift->{distfile};
}

sub installed {
    my $self = shift;
    $self->{installed} = shift if @_;
    $self->{installed};
}

sub is_core {
    my ($class, $package, $version) = @_;
    return 1 if $package eq "perl";
    return 1 if exists $Module::CoreList::version{$]}{$package};
    return;
}

sub providing {
    my ($self, $package, $version) = @_;
    for my $provide (@{$self->provides}) {
        return $self if $provide->{package} eq $package;
    }
    return;
}

sub equals {
    my ($self, $that) = @_;
    $self->distfile && $that->distfile and $self->distfile eq $that->distfile;
}

1;
