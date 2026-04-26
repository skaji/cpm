use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use File::Spec;
use Test::More;

use lib "xt/lib";
use CLI;

with_same_local {
    cpm_install 'Module::Build';
    my $r = cpm_install '--test', 'CPAN::Test::Dummy::Perl5::Build::DepeFails';
    isnt $r->exit, 0;
    my @log = split /\r?\n/, $r->log;
    like $log[-2], qr/The direct cause of the failure/;
    like $log[-1], qr/CPAN-Test-Dummy-Perl5-Build-Fails-\d/;
};

with_same_local {
    cpm_install 'Module::Build';
    my $r = cpm_install '--test', 'Data::Section::Simple', 'CPAN::Test::Dummy::Perl5::Build::DepeFails';
    isnt $r->exit, 0;
    ok -f File::Spec->catfile($r->local, qw(lib perl5 Data Section Simple.pm));
    like $r->err, qr/1 distribution installed/;
};

with_same_local {
    cpm_install 'Module::Build';
    my $r = cpm_install '--test', '--final-install=all', 'Data::Section::Simple', 'CPAN::Test::Dummy::Perl5::Build::DepeFails';
    isnt $r->exit, 0;
    ok -f File::Spec->catfile($r->local, qw(lib perl5 Data Section Simple.pm));
    ok -f File::Spec->catfile($r->local, qw(lib perl5 Test Requires.pm));
    like $r->err, qr/2 distributions installed/;
};

done_testing;
