use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
mirror 'https://www.cpan.org/';
requires 'File::pushd';
___

my $r = cpm_install "--cpanfile", "$cpanfile";
is $r->exit, 0 or diag $r->err;
like $r->log, qr{Resolved File::pushd.*https://www.cpan.org/.*from MetaDB};

$r = cpm_install "--mirror", "https://cpan.metacpan.org", "--cpanfile", "$cpanfile";
is $r->exit, 0 or diag $r->err;
like $r->log, qr{Resolved File::pushd.*https://cpan.metacpan.org/.*from MetaDB};

my $snapshot = Path::Tiny->tempfile;
$snapshot->spew(<<'___');
# carton snapshot format: version 1.0
DISTRIBUTIONS
  File-pushd-1.016
    pathname: D/DA/DAGOLDEN/File-pushd-1.016.tar.gz
    provides:
      File::pushd 1.016
    requirements:
___

$r = cpm_install "--cpanfile", "$cpanfile", "--snapshot", $snapshot;
is $r->exit, 0 or diag $r->err;
like $r->log, qr{Resolved File::pushd.*https://www.cpan.org/.*from Snapshot};

done_testing;
