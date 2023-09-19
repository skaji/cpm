use v5.16;
use warnings;
use Test::More;
use App::cpm::Requirement;

subtest basic => sub {
    my $r = App::cpm::Requirement->new('A' => 1, 'B' => 2);
    ok $r->add('A' => 2);
    ok $r->add('A' => 3);
    is_deeply $r->as_array, [
        { package => 'A', version_range => 3 },
        { package => 'B', version_range => 2 },
    ];
    {
        local $SIG{__WARN__} = sub {}; # XXX
        ok !$r->add('B' => '< 1.5');
    }
    ok $@;
    note $@;
};

subtest merge => sub {
    my $r1 = App::cpm::Requirement->new('A' => 1, 'B' => 2);
    my $r2 = App::cpm::Requirement->new('C' => 4, 'B' => 3);
    ok $r1->merge($r2);
    is_deeply $r1->as_array, [
        { package => 'A', version_range => 1 },
        { package => 'B', version_range => 3 },
        { package => 'C', version_range => 4 },
    ];
};


done_testing;
