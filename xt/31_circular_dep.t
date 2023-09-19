use v5.16;
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

like $r->log, qr/(Detected circular dependencies.*){3}/sm;

note $r->err;
note $r->log;

done_testing;
