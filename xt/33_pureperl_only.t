use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

subtest basic => sub {
    my $r = cpm_install '--pureperl-only', 'Scalar::Induce';
    is $r->exit, 0;
    unlike $r->log, qr{cc.*Scalar.Induce\.o};
    note $r->log;
};

subtest env => sub {
    local %ENV = %ENV;
    $ENV{PERL_MM_OPT} = "PUREPERL_ONLY=1";
    $ENV{PERL_MB_OPT} = "--pureperl-only";
    my $r = cpm_install 'Scalar::Induce';
    is $r->exit, 0;
    unlike $r->log, qr{cc.*Scalar.Induce\.o};
    like $r->log, qr/ExtUtils::MakeMaker options: PUREPERL_ONLY=1/;
    like $r->log, qr/Module::Build options: --pureperl-only/;
    note $r->log;
};

done_testing;
