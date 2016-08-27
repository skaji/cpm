use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'Geo::IP', v1.45.0;
___

my $r = cpm_install "--cpanfile", "$cpanfile";
like $r->err, qr/DONE install Geo-IP-/;
note explain $r;

done_testing;
