use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use App::cpm::Job;
use File::Temp 'tempdir';

my $tempdir = tempdir CLEANUP => 1;
my $base    = tempdir CLEANUP => 1;
my $cache   = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    base => $base,
    cache => $cache,
    mirror => "http://www.cpan.org",
);

my ($job, $result);

my $mirror = "http://www.cpan.org";
my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";

sub gen_default {
    my ($mirror, $distfile) = @_;
    return (
    source => "cpan",
    distfile => $distfile,
    uri => ["$mirror/authors/id/$distfile"],
    type => "fetch",
    );
}

my %default = gen_default($mirror, $distfile);

$job = App::cpm::Job->new(%default);
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok meta configure_requirements directory);

$job = App::cpm::Job->new(%default, %$result, type => "configure");
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok requirements distdata);

$job = App::cpm::Job->new(%default, %$result, type => "install");
$result = $installer->work($job);
ok exists $result->{$_} for qw(ok);

subtest 'both MB and EUMM in dist' => sub {

    # Data::Utilities 0.04 is a strange case, having both Build.PL and
    # Makefile.PL; furthermore, its Build.PL just invokes Makefile.PL to
    # produce a Makefile
    $installer = App::cpm::Worker::Installer->new(
        local_lib => $tempdir,
        base      => $base,
        cache     => $cache,
        mirror    => "http://backpan.cpan.org",
    );
    $mirror   = "http://www.cpan.org";
    $distfile = "C/CO/CORNELIS/Data-Utilities-0.04.tar.gz";
    %default  = gen_default($mirror, $distfile);

    $job    = App::cpm::Job->new(%default);
    $result = $installer->work($job);
    ok exists $result->{$_} for qw(ok meta configure_requirements directory);

    $job = App::cpm::Job->new( %default, %$result, type => "configure" );
    $result = $installer->work($job);
    ok exists $result->{$_} for qw(ok requirements distdata);

    $job = App::cpm::Job->new( %default, %$result, type => "install" );
    $result = $installer->work($job);
    ok exists $result->{$_} for qw(ok);
};

done_testing;
