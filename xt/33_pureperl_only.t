use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

my $r = cpm_install '--pureperl-only', 'Scalar::Induce';
is $r->exit, 0;
unlink $r->log, qr{cc.*Scalar.Induce\.o};
note $r->log;

done_testing;
