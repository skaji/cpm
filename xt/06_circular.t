use strict;
use warnings;
use Test::More;

use App::cpm::CircularDependency;

my $detector = App::cpm::CircularDependency->new;
$detector->add(
    'A',
    [{package => 'A1'}], # provides
    [{package => 'B1'}], # req
);
$detector->add(
    'B',
    [{package => 'B1'}], # provides
    [{package => 'C1'}], # req
);
$detector->add(
    'C',
    [{package => 'C1'}], # provides
    [{package => 'B1'}], # req
);
$detector->finalize;

my $result = $detector->detect;
note explain $result;

is scalar keys %$result, 3;
is_deeply $result->{A}, [qw(A B C B)];
is_deeply $result->{B}, [qw(B C B)];
is_deeply $result->{C}, [qw(C B C)];

done_testing;
