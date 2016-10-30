use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;

subtest basic => sub {
    my $r = cpm_install "App::FatPacker";
    like $r->err, qr/^DONE install App-FatPacker/;
    like $r->err, qr/1 distribution installed/;
    ok -f $r->local . "/bin/fatpack";

    $r = cpm_install "Distribution::Metadata";
    like $r->err, qr/^DONE install Distribution-Metadata/m or diag $r->err;
    ok -f $r->local . "/bin/which-meta";
};

subtest same => sub {
    with_same_local {
        my $r1 = cpm_install "App::FatPacker";
        my $r2 = cpm_install "App::FatPacker";
        like $r1->err, qr/^DONE install App-FatPacker/;
        like $r1->err, qr/1 distribution installed/;
        like $r2->err, qr/^DONE install App::FatPacker is up to date/;
        like $r2->err, qr/0 distribution installed/;
    };
};

subtest no_meta => sub {
    my $r = cpm_install "WWW::RobotRules::Extended";
    like $r->err, qr/^DONE install WWW-RobotRules-Extended/;
};

subtest invalid_meta => sub {
    plan skip_all => "Invalid ExtUtils::MakeMaker req 7.0401 (only found 7.04)";
    my $r = cpm_install "WWW::LinkedIn";
    like $r->err, qr/^DONE install WWW-LinkedIn/;
};

subtest test => sub {
    # File-pushd only in test requires
    my $r = cpm_install "Distribution::Metadata";
    unlike $r->err, qr/File-pushd/;

    $r = cpm_install "--no-test", "Distribution::Metadata";
    unlike $r->err, qr/File-pushd/;

    $r = cpm_install "--test", "Distribution::Metadata";
    like $r->err, qr/File-pushd/;
};

subtest range => sub {
    my $r = cpm_install "FormValidator::Lite"; # FormValidator::Lite has version range prereq
    is $r->exit, 0;
    like $r->err, qr/DONE install FormValidator-Lite/;
};

subtest http => sub {
    my $r;
    $r = cpm_install "http://www.cpan.org/authors/id/L/LE/LEONT/Module-Build-0.4220.tar.gz";
    is $r->exit, 0;
    $r = cpm_install "https://cpan.metacpan.org/authors/id/L/LE/LEONT/Module-Build-0.4220.tar.gz";
    is $r->exit, 0;
};

done_testing;
