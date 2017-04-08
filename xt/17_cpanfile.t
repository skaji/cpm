use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew(<<'___');
requires 'CPAN::Mirror::Tiny', '< 0.05';
requires 'HTTP::Tinyish', '== 0.06';
requires 'App::ChangeShebang',
    git => 'https://github.com/skaji/change-shebang',
    ref => '0.05';
___

my $r = cpm_install "--cpanfile", "$cpanfile";
is $r->exit, 0 or diag $r->err;
like $r->err, qr/DONE install CPAN-Mirror-Tiny-0.04/;
like $r->err, qr/DONE install HTTP-Tinyish-0.06/;
like $r->err, qr{DONE install https://github.com/skaji/change-shebang};
note $r->err;
my $file = path($r->local, "lib/perl5/App/ChangeShebang.pm");
my $content = $file->slurp_raw;
my $want = q{our $VERSION = '0.05';};
like $content, qr{\Q$want};

done_testing;
