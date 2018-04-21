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



$cpanfile->spew(<<'___');
requires 'Path::Class', 0.26,
  dist => "KWILLIAMS/Path-Class-0.26.tar.gz";

# omit version specifier
requires 'Hash::MultiValue',
  dist => "MIYAGAWA/Hash-MultiValue-0.15.tar.gz";

# use dist + mirror
requires 'Cookie::Baker',
  dist => "KAZEBURO/Cookie-Baker-0.08.tar.gz",
  mirror => "http://cpan.cpantesters.org/";

# use the full URL
requires 'Try::Tiny', 0.28,
  url => "http://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz";
___

$r = cpm_install "--cpanfile", "$cpanfile";
is $r->exit, 0;

like $r->log, qr/Hash-MultiValue-0\.15\| Successfully installed distribution/;
like $r->log, qr/Path-Class-0\.26\| Successfully installed distribution/;
like $r->log, qr/Cookie-Baker-0\.08\| Successfully installed distribution/;
like $r->log, qr!Fetching \Qhttp://cpan.cpantesters.org/authors/id/K/KA/KAZEBURO/Cookie-Baker-0.08.tar.gz\E!;
like $r->log, qr/Try-Tiny-0\.28\| Successfully installed distribution/;
like $r->log, qr!Fetching \Qhttp://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz\E!;

$cpanfile->spew(<<'___');
requires 'Path::Class', 0.26,
  url => "KWILLIAMS/Path-Class-0.26.tar.gz";
___
$r = cpm_install "--cpanfile", "$cpanfile";
isnt $r->exit, 0;
note $r->err;

$cpanfile->spew(<<'___');
requires 'Try::Tiny', 0.28,
  dist => "http://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz";
___
$r = cpm_install "--cpanfile", "$cpanfile";
isnt $r->exit, 0;
note $r->err;


done_testing;
