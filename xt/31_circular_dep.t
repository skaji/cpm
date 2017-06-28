use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

my $r = cpm_install 'CPAN::Test::Dummy::Perl5::Make::CircDepeOne', 'File::pushd';
isnt $r->exit, 0;
like $r->err, qr{DONE install File-pushd};
like $r->err, qr/FAIL install CPAN-Test-Dummy-Perl5-Make-CircDepeOne/;
like $r->err, qr/FAIL install CPAN-Test-Dummy-Perl5-Make-CircDepeThree/;
like $r->err, qr/FAIL install CPAN-Test-Dummy-Perl5-Make-CircDepeTwo/;

like $r->err, qr/(detect circular dependencies.*){3}/sm;
like $r->log, qr/(Circular dependencies are found.*){3}/sm;

note $r->err;
note $r->log;

done_testing;
