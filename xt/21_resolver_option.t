use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;
use File::Temp qw(tempdir);
use File::Path qw(mkpath);
use HTTP::Tinyish;
use CPAN::Mirror::Tiny;

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

with_same_home {
    my $base = tempdir;
    my $cpan = CPAN::Mirror::Tiny->new(base => $base);
    $cpan->inject('cpan:App::ChangeShebang@0.06');
    $cpan->write_index(compress => 1);

    my $yesterday = time - 24*60*60;
    utime $yesterday, $yesterday, "$base/modules/02packages.details.txt.gz";

    my $r = cpm_install "-v", "--resolver", "02packages,file://$base", "--resolver", "metadb", "App::ChangeShebang";
    like $r->err, qr/\QApp::ChangeShebang -> App-ChangeShebang-0.06 (from 02Packages)/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;

    $cpan->inject('cpan:Parallel::Pipes@0.001');
    $cpan->write_index(compress => 1);

    $r = cpm_install "-v", "--resolver", "02packages,file://$base", "--resolver", "metadb", "Parallel::Pipes";
    like $r->err, qr/\QParallel::Pipes -> Parallel-Pipes-0.001 (from 02Packages)/;
    like $r->err, qr/DONE install.*Parallel-Pipes-0.001/;
};

done_testing;
