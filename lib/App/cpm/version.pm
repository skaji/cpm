package App::cpm::version;
use strict;
use warnings;
use CPAN::Meta::Requirements;
our $VERSION = '0.293';

use parent 'version';

sub satisfy {
    my ($self, $version_range) = @_;

    return 1 unless $version_range;
    return $self >= version->parse($version_range) if $version_range =~ /^v?[\d_.]+$/;

    my $requirements = CPAN::Meta::Requirements->new;
    $requirements->add_string_requirement('DummyModule', $version_range);
    $requirements->accepts_module('DummyModule', $self->numify);
}

1;
