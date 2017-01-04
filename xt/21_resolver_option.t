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
  ExtUtils-MakeMaker-7.24
    pathname: B/BI/BINGOS/ExtUtils-MakeMaker-7.24.tar.gz
    provides:
      ExtUtils::Command 7.24
      ExtUtils::Command::MM 7.24
      ExtUtils::Liblist 7.24
      ExtUtils::Liblist::Kid 7.24
      ExtUtils::MM 7.24
      ExtUtils::MM_AIX 7.24
      ExtUtils::MM_Any 7.24
      ExtUtils::MM_BeOS 7.24
      ExtUtils::MM_Cygwin 7.24
      ExtUtils::MM_DOS 7.24
      ExtUtils::MM_Darwin 7.24
      ExtUtils::MM_MacOS 7.24
      ExtUtils::MM_NW5 7.24
      ExtUtils::MM_OS2 7.24
      ExtUtils::MM_QNX 7.24
      ExtUtils::MM_UWIN 7.24
      ExtUtils::MM_Unix 7.24
      ExtUtils::MM_VMS 7.24
      ExtUtils::MM_VOS 7.24
      ExtUtils::MM_Win32 7.24
      ExtUtils::MM_Win95 7.24
      ExtUtils::MY 7.24
      ExtUtils::MakeMaker 7.24
      ExtUtils::MakeMaker::Config 7.24
      ExtUtils::MakeMaker::Locale 7.24
      ExtUtils::MakeMaker::_version 7.24
      ExtUtils::MakeMaker::charstar 7.24
      ExtUtils::MakeMaker::version 7.24
      ExtUtils::MakeMaker::version::regex 7.24
      ExtUtils::MakeMaker::version::vpp 7.24
      ExtUtils::Mkbootstrap 7.24
      ExtUtils::Mksymlists 7.24
      ExtUtils::testlib 7.24
      MM 7.24
      MY 7.24
    requirements:
      Data::Dumper 0
      Encode 0
      File::Basename 0
      File::Spec 0.8
      Pod::Man 0
      perl 5.006
  ExtUtils-ParseXS-3.30
    pathname: S/SM/SMUELLER/ExtUtils-ParseXS-3.30.tar.gz
    provides:
      ExtUtils::ParseXS 3.30
      ExtUtils::ParseXS::Constants 3.30
      ExtUtils::ParseXS::CountLines 3.30
      ExtUtils::ParseXS::Eval 3.30
      ExtUtils::ParseXS::Utilities 3.30
      ExtUtils::Typemaps 3.30
      ExtUtils::Typemaps::Cmd 3.30
      ExtUtils::Typemaps::InputMap 3.30
      ExtUtils::Typemaps::OutputMap 3.30
      ExtUtils::Typemaps::Type 3.30
    requirements:
      Carp 0
      Cwd 0
      DynaLoader 0
      Exporter 5.57
      ExtUtils::CBuilder 0
      ExtUtils::MakeMaker 6.46
      File::Basename 0
      File::Spec 0
      Symbol 0
      Test::More 0.47
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
        my $base = tempdir(CLEANUP => 1);
        my $cpan = CPAN::Mirror::Tiny->new(base => $base);
        $cpan->inject('cpan:App::ChangeShebang@0.06');
        if ($] < 5.016) {
            $cpan->inject('cpan:ExtUtils::MakeMaker@7.24');
            $cpan->inject('cpan:ExtUtils::ParseXS@3.30');
        }
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
    my $base = tempdir(CLEANUP => 1);
    my $cpan = CPAN::Mirror::Tiny->new(base => $base);
    $cpan->inject('cpan:App::ChangeShebang@0.06');
    if ($] < 5.016) {
        $cpan->inject('cpan:ExtUtils::MakeMaker@7.24');
        $cpan->inject('cpan:ExtUtils::ParseXS@3.30');
    }
    $cpan->write_index(compress => 1);
    my $r = cpm_install "-v", "--resolver", "02packages,$base", "App::ChangeShebang";
    like $r->err, qr/\QApp::ChangeShebang -> App-ChangeShebang-0.06 (from 02Packages)/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;
};

done_testing;
