use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

with_same_local {
    cpm_install 'Module::Build';
    my $r = cpm_install '--test', 'CPAN::Test::Dummy::Perl5::Build::DepeFails';
    isnt $r->exit, 0;
    my @log = split /\r?\n/, $r->log;
    like $log[-2], qr/The direct cause of the failure/;
    like $log[-1], qr/CPAN-Test-Dummy-Perl5-Build-Fails-\d/;
};

done_testing;
