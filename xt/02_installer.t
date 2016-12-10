use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use App::cpm::Job;
use File::Temp 'tempdir';

my $tempdir = tempdir CLEANUP => 1;
my $menlo_base = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    menlo_base => $menlo_base,
    mirror => "http://www.cpan.org",
);

my ($job, $result);

my $mirror = "http://www.cpan.org";
my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";

my %default = (
    source => "cpan",
    distfile => $distfile,
    uri => ["$mirror/authors/id/$distfile"],
    type => "fetch",
);

$job = App::cpm::Job->new(%default);
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok meta configure_requirements directory);

$job = App::cpm::Job->new(%default, %$result, type => "configure");
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok requirements distdata);

$job = App::cpm::Job->new(%default, %$result, type => "install");
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok);

done_testing;
