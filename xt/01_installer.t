use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Installer;
use Config;
use File::Temp 'tempdir';

my $tempdir = tempdir CLEANUP => 1;
my $base    = tempdir CLEANUP => 1;
my $cache   = tempdir CLEANUP => 1;
my $installer = App::cpm::Worker::Installer->new(
    local_lib => $tempdir,
    base => $base,
    cache => $cache,
);

my $mirror = "http://www.cpan.org";
my $distfile = "S/SK/SKAJI/Distribution-Metadata-0.05.tar.gz";
my $job = { source => "cpan", uri => ["$mirror/authors/id/$distfile"], distfile => $distfile };
my ($dir, $meta, $configure_requirements) = $installer->fetch($job);

like $dir, qr{^/.*Distribution-Metadata-0\.05$}; # abs
ok scalar(keys %$meta);

if ($] < 5.016) {
    is_deeply $configure_requirements, [
        {package => "ExtUtils::MakeMaker", version_range => '6.58'},
        {package => "ExtUtils::ParseXS", version_range => ""},
    ];
} else {
    is_deeply $configure_requirements, [
        {package => "ExtUtils::MakeMaker", version_range => '0'},
    ];
}


my ($distdata, $requirements) = $installer->configure({
    directory => $dir,
    distfile => $distfile,
    meta => $meta,
    source => "cpan",
});

is $distdata->{distvname}, "Distribution-Metadata-0.05";

is_deeply $requirements->[-1], {
    package => "perl",
    version_range => "5.008001",
};

done_testing;
