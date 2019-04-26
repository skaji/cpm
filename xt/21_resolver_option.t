use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
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
  ExtUtils-CBuilder-0.280231
    pathname: A/AM/AMBS/ExtUtils-CBuilder-0.280231.tar.gz
    provides:
      ExtUtils::CBuilder 0.280231
      ExtUtils::CBuilder::Base 0.280231
      ExtUtils::CBuilder::Platform::Unix 0.280231
      ExtUtils::CBuilder::Platform::VMS 0.280231
      ExtUtils::CBuilder::Platform::Windows 0.280231
      ExtUtils::CBuilder::Platform::Windows::BCC 0.280231
      ExtUtils::CBuilder::Platform::Windows::GCC 0.280231
      ExtUtils::CBuilder::Platform::Windows::MSVC 0.280231
      ExtUtils::CBuilder::Platform::aix 0.280231
      ExtUtils::CBuilder::Platform::android 0.280231
      ExtUtils::CBuilder::Platform::cygwin 0.280231
      ExtUtils::CBuilder::Platform::darwin 0.280231
      ExtUtils::CBuilder::Platform::dec_osf 0.280231
      ExtUtils::CBuilder::Platform::os2 0.280231
    requirements:
      Cwd 0
      ExtUtils::MakeMaker 6.30
      File::Basename 0
      File::Spec 3.13
      File::Temp 0
      IO::File 0
      IPC::Cmd 0
      Perl::OSType 1
      Text::ParseWords 0
  ExtUtils-ParseXS-3.35
    pathname: S/SM/SMUELLER/ExtUtils-ParseXS-3.35.tar.gz
    provides:
      ExtUtils::ParseXS 3.35
      ExtUtils::ParseXS::Constants 3.35
      ExtUtils::ParseXS::CountLines 3.35
      ExtUtils::ParseXS::Eval 3.35
      ExtUtils::ParseXS::Utilities 3.35
      ExtUtils::Typemaps 3.35
      ExtUtils::Typemaps::Cmd 3.35
      ExtUtils::Typemaps::InputMap 3.35
      ExtUtils::Typemaps::OutputMap 3.35
      ExtUtils::Typemaps::Type 3.35
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
  IPC-Cmd-1.02
    pathname: B/BI/BINGOS/IPC-Cmd-1.02.tar.gz
    provides:
      IPC::Cmd 1.02
    requirements:
      ExtUtils::MakeMaker 0
      File::Spec 0
      File::Temp 0
      Locale::Maketext::Simple 0
      Module::Load::Conditional 0.66
      Params::Check 0.20
      Test::More 0
  Locale-Maketext-Simple-0.21
    pathname: J/JE/JESSE/Locale-Maketext-Simple-0.21.tar.gz
    provides:
      Locale::Maketext::Simple 0.21
    requirements:
      ExtUtils::MakeMaker 0
  Module-CoreList-5.20190420
    pathname: B/BI/BINGOS/Module-CoreList-5.20190420.tar.gz
    provides:
      Module::CoreList 5.20190420
      Module::CoreList::Utils 5.20190420
    requirements:
      ExtUtils::MakeMaker 0
      List::Util 0
      Test::More 0
      version 0.88
  Module-Load-0.34
    pathname: B/BI/BINGOS/Module-Load-0.34.tar.gz
    provides:
      Module::Load 0.34
    requirements:
      ExtUtils::MakeMaker 0
      Test::More 0.94
  Module-Load-Conditional-0.68
    pathname: B/BI/BINGOS/Module-Load-Conditional-0.68.tar.gz
    provides:
      Module::Load::Conditional 0.68
    requirements:
      ExtUtils::MakeMaker 0
      Locale::Maketext::Simple 0
      Module::CoreList 2.22
      Module::Load 0.28
      Module::Metadata 1.000005
      Params::Check 0
      Test::More 0
      version 0.69
  Module-Metadata-1.000036
    pathname: E/ET/ETHER/Module-Metadata-1.000036.tar.gz
    provides:
      Module::Metadata 1.000036
    requirements:
      Carp 0
      ExtUtils::MakeMaker 0
      Fcntl 0
      File::Find 0
      File::Spec 0
      perl 5.006
      strict 0
      version 0.87
      warnings 0
  Params-Check-0.38
    pathname: B/BI/BINGOS/Params-Check-0.38.tar.gz
    provides:
      Params::Check 0.38
    requirements:
      ExtUtils::MakeMaker 0
      Locale::Maketext::Simple 0
      Test::More 0
  Perl-OSType-1.010
    pathname: D/DA/DAGOLDEN/Perl-OSType-1.010.tar.gz
    provides:
      Perl::OSType 1.010
    requirements:
      Exporter 0
      ExtUtils::MakeMaker 6.17
      perl 5.006
      strict 0
      warnings 0
  common-sense-3.74
    pathname: M/ML/MLEHMANN/common-sense-3.74.tar.gz
    provides:
      common::sense 3.74
    requirements:
      ExtUtils::MakeMaker 0
  version-0.9924
    pathname: J/JP/JPEACOCK/version-0.9924.tar.gz
    provides:
      version 0.9924
      version::regex 0.9924
      version::vpp 0.9924
      version::vxs 0.9924
    requirements:
      ExtUtils::MakeMaker 0
      perl 5.006002
...
    my $r = cpm_install "-v", "--resolver", "snapshot", "--snapshot", $snapshot, "common::sense";
    is $r->exit, 0;
    like $r->err, qr/Snapshot/;
};

subtest '02packages_http' => sub {
    my $r = cpm_install "-v", "--resolver", "02packages,https://cpan.metacpan.org", "common::sense";
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
        if ($] < 5.010) {
            $cpan->inject('cpan:ExtUtils::CBuilder@0.280231');
            $cpan->inject('cpan:IPC::Cmd@1.02');
            $cpan->inject('cpan:Locale::Maketext::Simple@0.21');
            $cpan->inject('cpan:Module::CoreList@5.20190420');
            $cpan->inject('cpan:Module::Load@0.34');
            $cpan->inject('cpan:Module::Load::Conditional@0.68');
            $cpan->inject('cpan:Module::Metadata@1.000036');
            $cpan->inject('cpan:Params::Check@0.38');
            $cpan->inject('cpan:Perl::OSType@1.010');
            $cpan->inject('cpan:version@0.9924');
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
    if ($] < 5.010) {
        $cpan->inject('cpan:ExtUtils::CBuilder@0.280231');
        $cpan->inject('cpan:IPC::Cmd@1.02');
        $cpan->inject('cpan:Locale::Maketext::Simple@0.21');
        $cpan->inject('cpan:Module::CoreList@5.20190420');
        $cpan->inject('cpan:Module::Load@0.34');
        $cpan->inject('cpan:Module::Load::Conditional@0.68');
        $cpan->inject('cpan:Module::Metadata@1.000036');
        $cpan->inject('cpan:Params::Check@0.38');
        $cpan->inject('cpan:Perl::OSType@1.010');
        $cpan->inject('cpan:version@0.9924');
    }
    $cpan->write_index(compress => 1);
    my $r = cpm_install "-v", "--resolver", "02packages,$base", "App::ChangeShebang";
    like $r->err, qr/\QApp::ChangeShebang -> App-ChangeShebang-0.06 (from 02Packages)/;
    like $r->err, qr/DONE install.*App-ChangeShebang-0.06/;
};

done_testing;
