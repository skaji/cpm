package App::cpm::version;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use CPAN::Meta::Requirements;

use parent 'version';

sub satisfy ($self, $version_range) {

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
sub numify ($self, @args) {
    local $SIG{__WARN__} = sub (@) {};
    $self->SUPER::numify(@args);
}
sub parse ($self, @args) {
    local $SIG{__WARN__} = sub (@) {};
    $self->SUPER::parse(@args);
}

# utility function
sub range_merge ($range1, $range2) {
    my $req = CPAN::Meta::Requirements->new;
    $req->add_string_requirement('DummyModule', $_) for $range1, $range2; # may die
    $req->requirements_for_module('DummyModule');
}

1;
