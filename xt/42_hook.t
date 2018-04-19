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

my $cpanfile1 = Path::Tiny->tempfile; $cpanfile1->spew(<<'___');
requires 'App::ChangeShebang', '== 0.06', hook => sub {
    $_->patch('S/SK/SKAJI/patches/App-ChangeShebang-0.06.patch');
};
___
my $cpanfile2 = Path::Tiny->tempfile; $cpanfile2->spew(<<'___');
requires 'App::ChangeShebang', '== 0.06', hook => sub {
    $_->patch('SKAJI/patches/App-ChangeShebang-0.06.patch');
};
___

my $r1 = cpm_install '--cpanfile', $cpanfile1;
is $r1->exit, 0;
like $r1->log, qr{\QApp-ChangeShebang-0.06| Downloading patch https://cpan.metacpan.org/authors/id/S/SK/SKAJI/patches/App-ChangeShebang-0.06.patch};
like $r1->log, qr{\Qpatch at Makefile.PL line 11};

my $r2 = cpm_install '--cpanfile', $cpanfile2;
is $r2->exit, 0;
like $r2->log, qr{\QApp-ChangeShebang-0.06| Downloading patch https://cpan.metacpan.org/authors/id/S/SK/SKAJI/patches/App-ChangeShebang-0.06.patch};
like $r2->log, qr{\Qpatch at Makefile.PL line 11};

done_testing;
