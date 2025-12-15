use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

with_same_local {
    cpm_install 'CPAN::Test::Dummy::Perl5::cpm::Builder@1';
    my $r = cpm_install 'CPAN::Test::Dummy::Perl5::cpm::Module1';
    note $r->log;
    TODO: {
        local $TODO = "See https://github.com/skaji/cpm/issues/269";
        is $r->exit, 0;
    }
};

done_testing;
