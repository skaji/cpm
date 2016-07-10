#!/usr/bin/env perl
use 5.24.0;
use FindBin;
use App::FatPacker::Simple;
use App::cpm;
chdir "$FindBin::Bin/..";

my $exclude = join ",", qw(
  CPAN::Meta
  CPAN::Meta::Requirements
  ExtUtils::Config
  ExtUtils::Helpers
  ExtUtils::InstallPaths
  ExtUtils::MakeMaker::CPANfile
  Module::Build
  Module::Build::Tiny
  Test::Harness
);

my $shebang = <<'___';
#!/usr/bin/env perl
use 5.16.0;
___

sub cpm     { App::cpm->new->run(@_) }
sub fatpack { App::FatPacker::Simple->new->parse_options(@_)->run }

cpm "install", "--target-perl", "5.16.0";
fatpack "-o", "cpm", "-e", $exclude, "--shebang", $shebang, "script/cpm",
