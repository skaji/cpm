package App::cpm::version;
use strict;
use warnings;
use CPAN::Meta::Requirements;

use parent 'version';

sub satisfy {
    my ($self, $want_ver) = @_;

    return 1 unless $want_ver;
    return $self >= version->parse($want_ver) if $want_ver =~ /^v?[\d_.]+$/;

    my $requirements = CPAN::Meta::Requirements->new;
    $requirements->add_string_requirement('DummyModule', $want_ver);
    $requirements->accepts_module('DummyModule', $self->numify);
}

1;
