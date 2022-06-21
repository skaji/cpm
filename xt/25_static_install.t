use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

my $r = cpm_install "CPAN::Test::Dummy::Perl5::StaticInstall";
is $r->exit, 0;
like $r->log, qr/Distribution opts in x_static_install: 1/;
note $r->log;

$r = cpm_install "--no-static-install", "CPAN::Test::Dummy::Perl5::StaticInstall";
is $r->exit, 0;
unlike $r->log, qr/Distribution opts in x_static_install: 1/;
note $r->log;

done_testing;
