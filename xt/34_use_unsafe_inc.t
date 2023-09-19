use v5.16;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

my $r = cpm_install "--test", 'CPAN::Test::Dummy::Perl5::UseUnsafeINC::Fail@0.04';
is $r->exit, 0;
like $r->log, qr/Distribution opts in x_use_unsafe_inc: 0/; # XXX we see this line 3 times
note $r->log;

$r = cpm_install "--test", 'CPAN::Test::Dummy::Perl5::UseUnsafeINC::One@0.01';
is $r->exit, 0;
like $r->log, qr/Distribution opts in x_use_unsafe_inc: 1/; # XXX we see this line 3 times
note $r->log;

done_testing;
