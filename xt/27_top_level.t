use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny ();

my $cpanfile = Path::Tiny->tempfile; $cpanfile->spew(<<'___');
on test => sub {
    recommends 'CPAN::Test::Dummy::Perl5::ModuleBuild';
    suggests 'CPAN::Test::Dummy::Perl5::StaticInstall';
};

on develop => sub {
    requires 'Parallel::Pipes';
    recommends 'File::pushd';
    suggests 'Try::Tiny';
};

on configure => sub {
    requires 'Devel::CheckBin';
};
___

subtest 'normal' => sub () {
    my $r = cpm_install '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
};

subtest 'develop' => sub () {
    my $r = cpm_install '--top-level-phase', 'develop', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'recommends' => sub () {
    my $r = cpm_install '--top-level-relationship', 'recommends', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'suggests' => sub () {
    my $r = cpm_install '--top-level-relationship', 'suggests', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'mix1' => sub () {
    my $r = cpm_install
        '--top-level-phase', 'configure,test',
        '--top-level-relationship', 'requires,recommends',
        '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'mix2' => sub () {
    my $r = cpm_install
        '--top-level-phase', 'test,develop',
        '--top-level-relationship', 'requires,recommends,suggests',
        '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'with_develop compatibility' => sub () {
    my $r = cpm_install '--with-develop', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->err, qr/--with-develop is deprecated; use --top-level-phase and\/or --top-level-relationship instead\./;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

subtest 'with_without compatibility' => sub () {
    my $r = cpm_install '--with-recommends', '--without-test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->err, qr/--with-recommends is deprecated; use --top-level-phase and\/or --top-level-relationship instead\./;
    like   $r->err, qr/--without-test is deprecated; use --top-level-phase and\/or --top-level-relationship instead\./;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-ModuleBuild-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/CPAN-Test-Dummy-Perl5-StaticInstall-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Parallel-Pipes-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/File-pushd-[^\|]+\| Successfully installed distribution/;
    unlike $r->log, qr/Try-Tiny-[^\|]+\| Successfully installed distribution/;
    like   $r->log, qr/Devel-CheckBin-[^\|]+\| Successfully installed distribution/;
};

done_testing;
