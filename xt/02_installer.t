use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use File::Temp 'tempdir';

my $tempdir = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    mirror => "http://www.cpan.org",
);

my ($job, $result);

my $mirror = "http://www.cpan.org";
my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";
$job = {
    source => "cpan",
    distfile => "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz",
    uri => ["$mirror/authors/id/$distfile"],
    type => "fetch",
};
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok meta configure_requirements directory);

$job = {
    %$job,
    %$result,
    type => "configure",
};
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok requirements distdata);

$job = {
    %$job,
    %$result,
    type => "install",
};

$result = $installer->work($job);
$job = {
    %$job,
    %$result,
};
ok exists $result->{$_} for qw(ok);

done_testing;
