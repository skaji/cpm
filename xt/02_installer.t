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

$job = {
    distfile => "M/MI/MIYAGAWA/Plack-1.0037.tar.gz",
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
