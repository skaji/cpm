package App::cpm::version;
use v5.16;
use warnings;

use CPAN::Meta::Requirements::Range;

use parent 'version';

sub satisfy {
    my ($self, $version_range) = @_;

    return 1 unless $version_range;
    return $self >= (ref $self)->parse($version_range) if $version_range =~ /^v?[\d_.]+$/;

    my $req = CPAN::Meta::Requirements::Range->with_string_requirement($version_range);
    $req->accepts($self->numify);
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

# utility function
sub range_merge {
    my ($range1, $range2) = @_;
    my $req = CPAN::Meta::Requirements::Range
        ->with_string_requirement($range1)
        ->with_string_requirement($range2);
    $req->as_string;
}

1;
