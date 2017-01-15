package App::cpm::version;
use strict;
use warnings;
use CPAN::Meta::Requirements;
our $VERSION = '0.298';

use parent 'version';

sub satisfy {
    my ($self, $version_range) = @_;

    return 1 unless $version_range;
    return $self >= (ref $self)->parse($version_range) if $version_range =~ /^v?[\d_.]+$/;

    my $requirements = CPAN::Meta::Requirements->new;
    $requirements->add_string_requirement('DummyModule', $version_range);
    $requirements->accepts_module('DummyModule', $self->numify);
}

# suppress warnings
# > perl -Mwarnings -Mversion -e 'print version->parse("1.02_03")->numify'
# alpha->numify() is lossy at -e line 1.
# 1.020300
sub numify {
    local $SIG{__WARN__} = sub {};
    shift->SUPER::numify(@_);
}
sub parse {
    local $SIG{__WARN__} = sub {};
    shift->SUPER::parse(@_);
}

1;
