use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

my $r = cpm_install "CPAN::Test::Dummy::Perl5::Make::Failearly";
isnt $r->exit, 0;
like $r->log, qr/! Retrying/;
note $r->log;

$r = cpm_install "--no-retry", "CPAN::Test::Dummy::Perl5::Make::Failearly";
isnt $r->exit, 0;
unlike $r->log, qr/! Retrying/;
note $r->log;

done_testing;
