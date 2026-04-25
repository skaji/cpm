use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use File::Spec;
use Test::More;
use lib "xt/lib";
use CLI;

subtest no_meta => sub () {
    my $r = cpm_install "WWW::RobotRules::Extended";
    like $r->log, qr/WWW-RobotRules-Extended-[^\|]+\| Successfully installed distribution/;
};

subtest test => sub () {
    # Test::Requires only in test requires
    my $r = cpm_install "Data::Section::Simple";
    unlike $r->err, qr/Test-Requires/;

    $r = cpm_install "--no-test", "Data::Section::Simple";
    unlike $r->err, qr/Test-Requires/;

    with_same_local {
        cpm_install "ExtUtils::MakeMaker"; # no test for ExtUtils-MakeMaker
        $r = cpm_install "--test", "Data::Section::Simple";
        like $r->err, qr/Test-Requires/;
    };
};

subtest range => sub () {
    my $r = cpm_install "CPAN::Test::Dummy::Perl5::Deps::VersionRange";
    is $r->exit, 0;
    like $r->log, qr/CPAN-Test-Dummy-Perl5-Deps-VersionRange-[^\|]+\| Successfully installed distribution/;
};

subtest http => sub () {
    my $r = cpm_install "https://cpan.metacpan.org/authors/id/L/LE/LEONT/ExtUtils-Config-0.008.tar.gz";
    is $r->exit, 0;
    like $r->log, qr/ExtUtils-Config-0\.008\| Successfully installed distribution/;
};

subtest distfile => sub () {
    my $r = cpm_install "LEONT/ExtUtils-Config-0.008.tar.gz";
    is $r->exit, 0;
    like $r->log, qr/ExtUtils-Config-0\.008\| Successfully installed distribution/;
};

subtest use_install_command => sub () {
    my $r = cpm_install "--use-install-command", "ExtUtils::Config\@0.008";
    is $r->exit, 0;
    like $r->log, qr/ExtUtils-Config-0\.008\| Executing .+(?:g?make(?:\.EXE)?|nmake(?:\.exe)?) install/i;
};

subtest configure => sub () {
    # https://github.com/Ovid/Test-Differences/issues/13
    # https://rt.cpan.org/Ticket/Display.html?id=119616
    my $r = cpm_install 'Lingua::EN::Inflect@1.900';
    is $r->exit, 0;
    note $r->log;
};

subtest core => sub () {
    my $r = cpm_install "strict";
    is $r->exit, 0;
    like $r->err, qr/DONE install strict is a core module/;
};

done_testing;
