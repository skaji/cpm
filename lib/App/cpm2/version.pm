package App::cpm2::version;
use strict;
use warnings;

use CPAN::Meta::Requirements;

use parent 'version';

sub satisfy {
    my ($self, $version_range) = @_;

    return 1 unless $version_range;
    return $self >= (ref $self)->parse($version_range) if $version_range =~ /^v?[\d_.]+$/;

    my $requirements = CPAN::Meta::Requirements->new;
    $requirements->add_string_requirement('DummyModule', $version_range);
    $requirements->accepts_module('DummyModule', $self->numify);
}

sub numify {
    no warnings 'version';
    shift->SUPER::numify(@_);
}
sub parse {
    no warnings 'version';
    shift->SUPER::parse(@_);
}

sub merge {
    my ($range1, $range2) = @_;
    my $req = CPAN::Meta::Requirements->new;
    $req->add_string_requirement('DummyModule', $_) for $range1, $range2; # may die
    $req->requirements_for_module('DummyModule');
}

1;
