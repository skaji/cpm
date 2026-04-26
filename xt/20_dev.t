use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;

my ($r, $cpanfile);

$r = cpm_install
    'CPAN::Test::Dummy::Perl5::DevRelease',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.001\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.001\| Successfully installed distribution/;

$r = cpm_install
    'CPAN::Test::Dummy::Perl5::DevRelease@dev',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.002-TRIAL\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.001\| Successfully installed distribution/;

$r = cpm_install "--dev",
    'CPAN::Test::Dummy::Perl5::DevRelease',
    'CPAN::Test::Dummy::Perl5::DevRelease2';
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.002-TRIAL\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.002-TRIAL\| Successfully installed distribution/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease';
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--cpanfile", "$cpanfile";
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.001\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.001\| Successfully installed distribution/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease', dev => 1;
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--cpanfile", "$cpanfile";
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.002-TRIAL\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.001\| Successfully installed distribution/;

$cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Test::Dummy::Perl5::DevRelease';
requires 'CPAN::Test::Dummy::Perl5::DevRelease2';
___
$r = cpm_install "--dev", "--cpanfile", "$cpanfile";
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease-0\.002-TRIAL\| Successfully installed distribution/;
like $r->log, qr/CPAN-Test-Dummy-Perl5-DevRelease2-0\.002-TRIAL\| Successfully installed distribution/;

done_testing;
