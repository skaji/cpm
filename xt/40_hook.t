use strict;
use warnings;
use Test::More;
use Path::Tiny;
use File::Temp ();
use Cwd ();
use lib "xt/lib";
use CLI;

# https://gist.github.com/skaji/b06e47bdb4231c7793696c5f1814b2d7
plan skip_all => 'disable on APPVEYOR' if $ENV{APPVEYOR};

my $cwd = Cwd::cwd();
my $tempdir = File::Temp::tempdir(CLEANUP => 1);
chdir $tempdir;
END { chdir $cwd if $cwd } # for old File::Temp

path("cpanfile")->spew(<<'___');
requires 'App::FatPacker', '== 0.010007', hook => sub {
    $_->patch('./hoge.patch');
    $_->add_configure_requires('common::sense' => 0);
    $_->add_requires('File::pushd' => 1);
    $_->configure_args('CONFIGURE_ARGS1=1', 'CONFIGURE_ARGS2=2');
    $_->build_args('BUILD_ARGS1=1', 'BUILD_ARGS2=2');
    $_->test_args('TEST_ARGS1=1', 'TEST_ARGS2=2');
    $_->install_args('INSTALL_ARGS1=1', 'INSTALL_ARGS2=2');
    $_->env('FOO' => 'A', 'BAR' => 'B');
    $_->pureperl_only(1);
};
___

path("hoge.patch")->spew(<<'___');
diff --git Makefile.PL Makefile.PL
index 1077f48..8a8c7d9 100644
--- Makefile.PL
+++ Makefile.PL
@@ -6,6 +6,8 @@ use 5.008000;
 
 (do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';
 
+warn "HOOKED";
+
 WriteMakefile(
   NAME => 'App::FatPacker',
   VERSION_FROM => 'lib/App/FatPacker.pm',
___

my $r = cpm_install;
is $r->exit, 0;

my $log = $r->log;
my $prefix = qr{App-FatPacker-.*\|};
like $log, qr{$prefix Applying patch ./hoge.patch};
if ($^O eq 'MSWin32') {
    like $log, qr{HOOKED at Makefile.PL line 9.};
} else {
    like $log, qr{$prefix HOOKED at Makefile.PL line 9.};
}
like $log, qr{$prefix Found configure dependencies: common::sense \(0\)};
like $log, qr{$prefix Found dependencies: File::pushd \(1\)};
like $log, qr{$prefix Set environment variables BAR=B FOO=A.*$prefix Set environment variables BAR=B FOO=A}s; # twice
my $q = q{["']?}; # for windows
like $log, qr{$prefix Executing $q.*perl.*$q ${q}Makefile.PL${q} ${q}CONFIGURE_ARGS1=1${q} ${q}CONFIGURE_ARGS2=2${q} ${q}PUREPERL_ONLY=1${q}};
like $log, qr{$prefix Executing $q.*make.*$q ${q}BUILD_ARGS1=1${q} ${q}BUILD_ARGS2=2${q}};
like $log, qr{$prefix Executing $q.*make.*$q ${q}install${q} ${q}INSTALL_ARGS1=1${q} ${q}INSTALL_ARGS2=2${q}};

if ($] >= 5.012) {
    like   $log, qr{File-pushd-.*\| Saving the build};
    like   $log, qr{common-sense-.*\| Saving the build};
    unlike $log, qr{$prefix Saving the build};
}

note $log;

done_testing;
