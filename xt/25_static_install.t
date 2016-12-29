use strict;
use warnings;
use Test::More;
use xt::CLI;

plan skip_all => "skip if perl < 5.012" if $] < 5.012;

my $r = cpm_install "CPAN::Test::Dummy::Perl5::StaticInstall";
is $r->exit, 0;
like $r->log, qr/Distribution opts in x_static_install: 1/;
note $r->log;

done_testing;
