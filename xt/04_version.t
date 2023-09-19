use v5.16;
use warnings;
use Test::More;
use App::cpm::version;

my $v = App::cpm::version->parse("0.02");

ok $v->satisfy("0.01");
ok $v->satisfy("0.02");
ok $v->satisfy("!= 0.01");
ok $v->satisfy("== 0.02");
ok $v->satisfy("> 0.01");
ok $v->satisfy(">= 0.02");
ok $v->satisfy("< 0.03");
ok !$v->satisfy("> 0.01, != 0.02");
ok !$v->satisfy("<= 0.01");

done_testing;
