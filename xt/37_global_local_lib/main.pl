#!/usr/bin/env perl
use strict;
use warnings;

use Capture::Tiny qw(capture);
use Config;
use File::Temp ();

my $local = File::Temp->newdir;

my @case = (
    { name => "global_local_lib", install_base => $ENV{_TEST_DIR}, options => ["--reinstall", "--global"] },
    { name => "local", install_base => $local, options => ["-L", $local] },
);

my $OK = 1;
for my $case (@case) {
    my $home = File::Temp->newdir;
    my $install_base = $case->{install_base};

    my ($stdout, $stderr, $exit) = capture {
        my @resolver;
        if ($] < 5.010) {
            @resolver = ("--resolver", 'Fixed,CPAN::Meta::Requirements@2.140');
        }
        system $^X, "-Ilib", "script/cpm", "install", @resolver, "--home", $home, @{$case->{options}},
            "common::sense\@3.75", # ExtUtils::MakeMaker
            "CPAN::Test::Dummy::Perl5::ModuleBuild\@0.001", # Module::Build
            "Darwin::InitObjC\@0.001", # static install
    };

    my @want = map { "$case->{install_base}/$_" } (
        "lib/perl5/$Config{archname}/.meta/CPAN-Test-Dummy-Perl5-ModuleBuild-0.001/MYMETA.json",
        "lib/perl5/$Config{archname}/.meta/CPAN-Test-Dummy-Perl5-ModuleBuild-0.001/install.json",
        "lib/perl5/$Config{archname}/.meta/Darwin-InitObjC-0.001/MYMETA.json",
        "lib/perl5/$Config{archname}/.meta/Darwin-InitObjC-0.001/install.json",
        "lib/perl5/$Config{archname}/.meta/common-sense-3.75/MYMETA.json",
        "lib/perl5/$Config{archname}/.meta/common-sense-3.75/install.json",
        "lib/perl5/$Config{archname}/auto/CPAN/Test/Dummy/Perl5/ModuleBuild/.packlist",
        "lib/perl5/$Config{archname}/auto/Darwin/InitObjC/.packlist",
        "lib/perl5/$Config{archname}/auto/common/sense/.packlist",
        "lib/perl5/$Config{archname}/common/sense.pm",
        "lib/perl5/$Config{archname}/common/sense.pod",
        "lib/perl5/$Config{archname}/perllocal.pod",
        "lib/perl5/CPAN/Test/Dummy/Perl5/ModuleBuild.pm",
        "lib/perl5/Darwin/InitObjC.pm",
    );

    my $ok = 1;
    for my $want (@want) {
        if (-f $want) {
            warn "---> [$case->{name}] found $want\n" if $ENV{HARNESS_IS_VERBOSE};
        } else {
            warn "---> [$case->{name}] missing $want\n";
            $ok = 0;
        }
    }
    if (!$ok) {
        $OK = 0;
        open my $fh, "<", "$home/build.log" or die;
        warn $_ for <$fh>;
        system "find $install_base -type f >&2";
    }
}

if (!$OK) {
    exit 1;
}
