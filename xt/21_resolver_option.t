use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

my $r;
$r = cpm_install "-v", "--resolver", "metadb", "common::sense";
like $r->err, qr/MetaDB/;

$r = cpm_install "-v", "--resolver", "metacpan", "common::sense";
like $r->err, qr/MetaCPAN/;

my $snapshot = Path::Tiny->tempfile;
$snapshot->spew(<<'...');
# carton snapshot format: version 1.0
DISTRIBUTIONS
  common-sense-3.74
    pathname: M/ML/MLEHMANN/common-sense-3.74.tar.gz
    provides:
      common::sense 3.74
    requirements:
      ExtUtils::MakeMaker 0
...
$r = cpm_install "-v", "--resolver", "snapshot", "--snapshot", $snapshot, "common::sense";
like $r->err, qr/Snapshot/;

$r = cpm_install "-v", "--resolver", "02packages,http://www.cpan.org", "common::sense";
like $r->err, qr/02Packages/;

my $index = Path::Tiny->tempfile;
$index->spew(<<"...");
dummy header

common::sense 3.74 M/ML/MLEHMANN/common-sense-3.74.tar.gz
...
$r = cpm_install "-v", "--resolver", "02packages,$index,http://www.cpan.org", "common::sense";
like $r->err, qr/02Packages/;

done_testing;
