use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use Config;
use File::Temp 'tempdir';
use File::Spec;

my $tempdir = tempdir CLEANUP => 1;
my $base    = tempdir CLEANUP => 1;
my $cache   = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    base => $base,
    cache => $cache,
);

my $mirror = "https://cpan.metacpan.org";
my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";
my $job = { source => "cpan", uri => ["$mirror/authors/id/$distfile"], distfile => $distfile };
my $result = $installer->fetch($job);

ok(File::Spec->file_name_is_absolute($result->{directory}));
like $result->{directory}, qr{\bDistribution-Metadata-0\.05$};
ok scalar(keys %{$result->{meta}});

my %reqs = map {; ($_->{package} => $_->{version_range}) } @{$result->{configure_requirements}};

is_deeply \%reqs, {
    "ExtUtils::MakeMaker" => $] < 5.016 ? '6.58' : '0',
};

$result = $installer->configure({
    directory => $result->{directory},
    distfile => $distfile,
    meta => $result->{meta},
    source => "cpan",
});

is $result->{distdata}{distvname}, "Distribution-Metadata-0.05";

is_deeply $result->{requirements}[-1], {
    package => "perl",
    version_range => "5.008001",
};

done_testing;
