use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'Geo::IP', v1.45.0;
___

my $r = cpm_install "--cpanfile", "$cpanfile";
like $r->log, qr/Geo-IP-[^\|]+\| Successfully installed distribution/;
note explain $r;

done_testing;
