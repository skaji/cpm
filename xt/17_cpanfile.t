use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'Plack', "< 1.0030";
requires 'Amon2', "== 6.12";
requires 'App::ChangeShebang',
    git => 'https://github.com/skaji/change-shebang',
    ref => '0.05';
___

my $r = cpm_install "--cpanfile", "$cpanfile";
is $r->exit, 0 or diag $r->err;
like $r->err, qr/DONE install Plack-1\.0029/;
like $r->err, qr/DONE install Amon2-6\.12/;
like $r->err, qr{DONE install https://github.com/skaji/change-shebang};
note $r->err;
my $file = path($r->local, "lib/perl5/App/ChangeShebang.pm");
my $content = $file->slurp_raw;
my $want = q{our $VERSION = '0.05';};
like $content, qr{\Q$want};

done_testing;
