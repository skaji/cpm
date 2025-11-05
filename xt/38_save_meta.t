use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

use Config;
use JSON::PP;

sub read_json_file {
    my $path = shift;
    open my $fh, "<", $path or die "$!: $path";
    JSON::PP::decode_json join "", <$fh>;
}

with_same_home {
    for my $times (1..2) { # 1 for normal install, 2 for prebuilt
        my $res = cpm_install
            "common::sense\@3.75", # ExtUtils::MakeMaker
            "CPAN::Test::Dummy::Perl5::ModuleBuild\@0.001", # Module::Build
            "Darwin::InitObjC\@0.001", # static install
        ;
        is $res->exit, 0;

        if ($times == 1) {
            unlike $res->err, qr/prebuilt/;
        } elsif ($times == 2 && $] >= 5.012) {
            like $res->err, qr/prebuilt/;
        }

        my $local = $res->local;
        my ($file, $json);

        $file = "$local/lib/perl5/$Config{archname}/.meta/Darwin-InitObjC-0.001/MYMETA.json";
        $json = read_json_file $file;
        is $json->{name}, "Darwin-InitObjC";
        $file = "$local/lib/perl5/$Config{archname}/.meta/Darwin-InitObjC-0.001/install.json";
        $json = read_json_file $file;
        is $json->{provides}{"Darwin::InitObjC"}{version}, "0.001";

        $file = "$local/lib/perl5/$Config{archname}/.meta/common-sense-3.75/MYMETA.json";
        $json = read_json_file $file;
        is $json->{name}, "common-sense";
        $file = "$local/lib/perl5/$Config{archname}/.meta/common-sense-3.75/install.json";
        $json = read_json_file $file;
        is $json->{provides}{"common::sense"}{version}, "3.75";

        $file = "$local/lib/perl5/$Config{archname}/.meta/CPAN-Test-Dummy-Perl5-ModuleBuild-0.001/MYMETA.json";
        $json = read_json_file $file;
        is $json->{name}, "CPAN-Test-Dummy-Perl5-ModuleBuild";
        $file = "$local/lib/perl5/$Config{archname}/.meta/CPAN-Test-Dummy-Perl5-ModuleBuild-0.001/install.json";
        $json = read_json_file $file;
        is $json->{provides}{"CPAN::Test::Dummy::Perl5::ModuleBuild"}{version}, "0.001";
    }
};

done_testing;
