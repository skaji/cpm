use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;

subtest module_build => sub {
    my $r = cpm_install 'Module::Build@0.4203';
    is $r->exit, 0;
    like $r->err, qr/^DONE install Module-Build/;
};

done_testing;
