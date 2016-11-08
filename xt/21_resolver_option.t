use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;
use File::Temp qw(tempdir);
use File::Path qw(mkpath);
use HTTP::Tinyish;
use CPAN::Mirror::Tiny;

subtest metadb => sub {
    my $r = cpm_install "-v", "--resolver", "metadb", "common::sense";
    is $r->exit, 0;
    like $r->err, qr/MetaDB/;
};

subtest metacpan => sub {
    my $r = cpm_install "-v", "--resolver", "metacpan", "common::sense";
    is $r->exit, 0;
    like $r->err, qr/MetaCPAN/;
};

subtest snapshot => sub {
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
    my $r = cpm_install "-v", "--resolver", "snapshot", "--snapshot", $snapshot, "common::sense";
    is $r->exit, 0;
    like $r->err, qr/Snapshot/;
};

subtest '02packages_http' => sub {
    my $r = cpm_install "-v", "--resolver", "02packages,http://www.cpan.org", "common::sense";
    is $r->exit, 0;
    like $r->err, qr/02Packages/;
};

subtest '02packages_file' => sub {
    with_same_home {
        my $base = tempdir;
        my $cpan = CPAN::Mirror::Tiny->new(base => $base);
        $cpan->inject('cpan:App::ChangeShebang@0.06');
        $cpan->write_index(compress => 1);

        my $yesterday = time - 24*60*60;
        utime $yesterday, $yesterday, "$base/modules/02packages.details.txt.gz";

        my $r = cpm_install "-v", "--resolver", "02packages,file://$base", "App::ChangeShebang";
        is $r->exit, 0;
        like $r->err, qr/\QApp::ChangeShebang -> App-ChangeShebang-0.06 (from 02Packages)/;
        like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;

        $cpan->inject('cpan:Parallel::Pipes@0.001');
        $cpan->write_index(compress => 1);

        $r = cpm_install "-v", "--resolver", "02packages,file://$base", "Parallel::Pipes";
        is $r->exit, 0;
        like $r->err, qr/\QParallel::Pipes -> Parallel-Pipes-0.001 (from 02Packages)/;
        like $r->err, qr/DONE install.*Parallel-Pipes-0.001/;
    };
};

subtest '02packages_file_no_prefix' => sub {
    my $base = tempdir;
    my $cpan = CPAN::Mirror::Tiny->new(base => $base);
    $cpan->inject('cpan:App::ChangeShebang@0.06');
    $cpan->write_index(compress => 1);
    my $r = cpm_install "-v", "--resolver", "02packages,$base", "App::ChangeShebang";
    like $r->err, qr/\QApp::ChangeShebang -> App-ChangeShebang-0.06 (from 02Packages)/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;
};

done_testing;
