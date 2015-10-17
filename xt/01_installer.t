use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use Config;
use File::Temp 'tempdir';

my $tempdir = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    mirror => "http://www.cpan.org",
);

my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";
my ($dir, $meta, $configure_requirements) = $installer->fetch($distfile);

like $dir, qr{^/.*Distribution-Metadata-0\.05$}; # abs
ok scalar(keys %$meta);
is_deeply $configure_requirements, [
  {
    package => "ExtUtils::MakeMaker",
    phase   => "configure",
    type    => "requires",
    version => 0,
  },
];

my ($distdata, $requirements) = $installer->configure($dir, $distfile, $meta);

is $distdata->{distvname}, "Distribution-Metadata-0.05";

is_deeply $requirements->[-1], {
    package => "perl",
    phase   => "runtime",
    type    => "requires",
    version => "5.008001",
};

my $ok = $installer->install($dir, $distdata);

ok $ok;

my @file = qw(
    bin/which-meta
    lib/perl5/Distribution/Metadata.pm
);
push @file, "lib/perl5/$Config{archname}/.meta/Distribution-Metadata-0.05/MYMETA.json";

for my $file (@file) {
    ok -f "$tempdir/$file" or diag "$file missing";
}

done_testing;
