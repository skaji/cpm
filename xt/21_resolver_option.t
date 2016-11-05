use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;
use File::Temp qw(tempdir);
use File::Path qw(mkpath);
use HTTP::Tinyish;

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
    my $darkpan = tempdir;
    mkpath("$darkpan/modules");
    mkpath("$darkpan/authors/id/S/SK/SKAJI");
    HTTP::Tinyish->new->mirror(
        "http://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-ChangeShebang-0.06.tar.gz",
        "$darkpan/authors/id/S/SK/SKAJI/App-ChangeShebang-0.06.tar.gz",
    )->{success} or die;
    HTTP::Tinyish->new->mirror(
        "http://cpan.metacpan.org/authors/id/S/SK/SKAJI/App-ChangeShebang-0.05.tar.gz",
        "$darkpan/authors/id/S/SK/SKAJI/App-ChangeShebang-0.05.tar.gz",
    )->{success} or die;

    my $index = "$darkpan/modules/02packages.details.txt";
    path($index)->spew("dummy header\n\nApp::ChangeShebang 0.05 S/SK/SKAJI/App-ChangeShebang-0.05.tar.gz\n");
    !system "gzip", $index or die;
    my $yesterday = time - 24*60*60;
    utime $yesterday, $yesterday, "$index.gz";

    my $r = cpm_install "-v", "--resolver", "02packages,file://$darkpan", "App::ChangeShebang";
    like $r->err, qr/02Packages/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.05/;

    unlink "$index.gz";
    path($index)->spew("dummy header\n\nApp::ChangeShebang 0.06 S/SK/SKAJI/App-ChangeShebang-0.06.tar.gz\n");
    !system "gzip", $index or die;

    $r = cpm_install "-v", "--resolver", "02packages,file://$darkpan", "App::ChangeShebang";
    like $r->err, qr/02Packages/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;
};

done_testing;
