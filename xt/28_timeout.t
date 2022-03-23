use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

my $r = cpm_install "--configure-timeout", 2,
    "https://github.com/skaji/CPAN-Test-Dummy-Perl5-SleepSteps.git",
    "File::pushd";
isnt $r->exit, 0;
like $r->err, qr{DONE install File-pushd};
like $r->err, qr{FAIL install https://github.com/skaji/CPAN-Test-Dummy-Perl5-SleepSteps.git};
like $r->err, qr{See .* for details};

# TODO do not retry
like $r->log, qr{\QTimed out (> 2s)};
note $r->log;

done_testing;
