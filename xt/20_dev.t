use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

my ($r, $cpanfile);

$r = cpm_install
    'CPAN::Test::Dummy::Perl5::DevRelease',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.001/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.001/;

$r = cpm_install
    'CPAN::Test::Dummy::Perl5::DevRelease@dev',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.002-TRIAL/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.001/;

$r = cpm_install "--dev",
    'CPAN::Test::Dummy::Perl5::DevRelease',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.002-TRIAL/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.002-TRIAL/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease';
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--cpanfile", "$cpanfile";
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.001/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.001/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease', dev => 1;
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--cpanfile", "$cpanfile";
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.002-TRIAL/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.001/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease';
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--dev", "--cpanfile", "$cpanfile";
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease-0.002-TRIAL/;
like $r->err, qr/DONE install CPAN-Test-Dummy-Perl5-DevRelease2-0.002-TRIAL/;

done_testing;
