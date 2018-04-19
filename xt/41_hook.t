use strict;
use warnings;
use Test::More;
use Path::Tiny;
use File::Path 'mkpath';
use File::Temp ();
use Cwd ();
use CPAN::Mirror::Tiny;
use lib "xt/lib";
use CLI;

# https://gist.github.com/skaji/b06e47bdb4231c7793696c5f1814b2d7
plan skip_all => 'disable on APPVEYOR' if $ENV{APPVEYOR};

my $base = File::Temp::tempdir(CLEANUP => 1);
my $cpan = CPAN::Mirror::Tiny->new(base => $base);
$cpan->inject('cpan:App::FatPacker@0.010007');

my $cpanfile = Path::Tiny->tempfile; $cpanfile->spew(<<'___');
requires 'App::FatPacker', hook => sub {
    $_->patch('https://gist.githubusercontent.com/skaji/7130339dd34bbc47c54ecf2c574e31cf/raw/f1bc04c168275e206a3350f54216f5f3379b9fcc/cpm-test.patch');
    $_->patch('S/SK/SKAJI/patches/patch1');
    $_->patch('SKAJI/patches/patch2');
};
___

mkpath "$base/authors/id/S/SK/SKAJI/patches";
my $patch1 = path("$base/authors/id/S/SK/SKAJI/patches/patch1")->spew(<<'___');
diff --git Makefile.PL Makefile.PL
index 8a8c7d9..4e94995 100644
--- Makefile.PL
+++ Makefile.PL
@@ -7,6 +7,7 @@ use 5.008000;
 (do 'maint/Makefile.PL.include' or die $@) unless -f 'META.yml';
 
 warn "HOOKED";
+warn "patch1";
 
 WriteMakefile(
   NAME => 'App::FatPacker',
___

my $patch2 = path("$base/authors/id/S/SK/SKAJI/patches/patch2")->spew(<<'___');
diff --git Makefile.PL Makefile.PL
index 4e94995..58294a4 100644
--- Makefile.PL
+++ Makefile.PL
@@ -8,6 +8,7 @@ use 5.008000;
 
 warn "HOOKED";
 warn "patch1";
+warn "patch2";
 
 WriteMakefile(
   NAME => 'App::FatPacker',
___

my $r = cpm_install '--mirror', "file://$base", '--cpanfile', $cpanfile;
is $r->exit, 0;

my $log = $r->log;
my $prefix = qr{App-FatPacker-.*\|};
if ($^O eq 'MSWin32') {
    like $log, qr{HOOKED at Makefile.PL line 9.};
    like $log, qr{patch1 at Makefile.PL line 10.};
    like $log, qr{patch2 at Makefile.PL line 11.};
} else {
    like $log, qr{$prefix HOOKED at Makefile.PL line 9.};
    like $log, qr{$prefix patch1 at Makefile.PL line 10.};
    like $log, qr{$prefix patch2 at Makefile.PL line 11.};
}
note $log;

done_testing;
