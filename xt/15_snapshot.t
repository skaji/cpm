use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'Distribution::Metadata', '== 0.04';
___

my $snapshot = Path::Tiny->tempfile;
$snapshot->spew(<<'___');
# carton snapshot format: version 1.0
DISTRIBUTIONS
  CPAN-DistnameInfo-0.12
    pathname: G/GB/GBARR/CPAN-DistnameInfo-0.12.tar.gz
    provides:
      CPAN::DistnameInfo 0.12
    requirements:
      ExtUtils::MakeMaker 0
      Test::More 0
  Distribution-Metadata-0.04
    pathname: S/SK/SKAJI/Distribution-Metadata-0.04.tar.gz
    provides:
      Distribution::Metadata 0.04
      Distribution::Metadata::Factory undef
    requirements:
      CPAN::DistnameInfo 0
      CPAN::Meta 0
      ExtUtils::MakeMaker 0
      ExtUtils::Packlist 0
      JSON 0
      Module::Metadata 0
      perl 5.008001
  JSON-2.90
    pathname: M/MA/MAKAMAKA/JSON-2.90.tar.gz
    provides:
      JSON 2.90
      JSON::Backend::PP 2.90
      JSON::Boolean 2.90
    requirements:
      ExtUtils::MakeMaker 0
      Test::More 0
___


my $r;
with_same_local {
    $r = cpm_install "--cpanfile", $cpanfile->stringify, "--snapshot", $snapshot->stringify;
    like $r->err, qr/DONE install Distribution-Metadata-0.04/;
    note explain $r;

    $r = cpm_install "--cpanfile", $cpanfile->stringify, "--snapshot", $snapshot->stringify;
    like $r->err, qr/All requirements are satisfied\./;
    note explain $r;
};

done_testing;
