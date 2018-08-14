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
requires 'Try::Tiny',
    url => 'https://cpan.metacpan.org/authors/id/E/ET/ETHER/Try-Tiny-0.30.tar.gz';
___

with_same_local {
    my $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0 or diag $r->err;
    like $r->err, qr/DONE install CPAN-Mirror-Tiny-0.04/;
    like $r->err, qr/DONE install HTTP-Tinyish-0.06/;
    like $r->err, qr{DONE install App-ChangeShebang-0.05 \(https://github.com/skaji/change-shebang\@4d2de546e80c29b74afd1e8dadb301b004e020cb\)};
    like $r->err, qr/DONE install Try-Tiny-0.30/;
    like $r->log, qr/Resolved CPAN::Mirror::Tiny.*from MetaDB/;
    like $r->log, qr/Resolved HTTP::Tinyish.*from MetaDB/;
    like $r->log, qr/Resolved App::ChangeShebang.*from Git/;
    like $r->log, qr/Resolved Try::Tiny.*from CPANfile/;
    note $r->err;
    my $file = path($r->local, "lib/perl5/App/ChangeShebang.pm");
    my $content = $file->slurp_raw;
    my $want = q{our $VERSION = '0.05'; # 4d2de546e80c29b74afd1e8dadb301b004e020cb};
    like $content, qr{\Q$want};

    # 2nd time; only install git
    $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0;
    like $r->err, qr/DONE install App::ChangeShebang is up to date\. \(0\.05\)/;
    unlike $r->err, qr/CPAN-Mirror-Tiny/;
    unlike $r->err, qr/HTTP-Tinyish/;
    unlike $r->err, qr/Try-Tiny/;
};


$cpanfile->spew(<<'___');
requires 'CPAN::Mirror::Tiny', '< 0.05';
requires 'HTTP::Tinyish', '== 0.06';
requires 'App::ChangeShebang', '== 0.05',
    git => 'https://github.com/skaji/change-shebang';
requires 'Try::Tiny',
    url => 'https://cpan.metacpan.org/authors/id/E/ET/ETHER/Try-Tiny-0.30.tar.gz';
___

with_same_local {
    my $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0 or diag $r->err;
    like $r->err, qr/DONE install CPAN-Mirror-Tiny-0.04/;
    like $r->err, qr/DONE install HTTP-Tinyish-0.06/;
    like $r->err, qr{DONE install App-ChangeShebang-0.05 \(https://github.com/skaji/change-shebang\@4d2de546e80c29b74afd1e8dadb301b004e020cb\)};
    like $r->err, qr/DONE install Try-Tiny-0.30/;
    like $r->log, qr/Resolved CPAN::Mirror::Tiny.*from MetaDB/;
    like $r->log, qr/Resolved HTTP::Tinyish.*from MetaDB/;
    like $r->log, qr/Resolved App::ChangeShebang.*from Git/;
    like $r->log, qr/Resolved Try::Tiny.*from CPANfile/;
    note $r->err;
    my $file = path($r->local, "lib/perl5/App/ChangeShebang.pm");
    my $content = $file->slurp_raw;
    my $want = q{our $VERSION = '0.05'; # 4d2de546e80c29b74afd1e8dadb301b004e020cb};
    like $content, qr{\Q$want};

    # 2nd time; only install git
    $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0;
    like $r->err, qr/All requirements are satisfied/;
};


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

with_same_local {
    my $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0;

    like $r->log, qr/Hash-MultiValue-0\.15\| Successfully installed distribution/;
    like $r->log, qr/Path-Class-0\.26\| Successfully installed distribution/;
    like $r->log, qr/Cookie-Baker-0\.08\| Successfully installed distribution/;
    like $r->log, qr!Fetching \Qhttp://cpan.cpantesters.org/authors/id/K/KA/KAZEBURO/Cookie-Baker-0.08.tar.gz\E!;
    like $r->log, qr/Try-Tiny-0\.28\| Successfully installed distribution/;
    like $r->log, qr!Fetching \Qhttp://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz\E!;

    $r = cpm_install "--cpanfile", "$cpanfile";
    is $r->exit, 0;
    like $r->err, qr/All requirements are satisfied/;
};

$cpanfile->spew(<<'___');
requires 'Path::Class', 0.26,
  url => "KWILLIAMS/Path-Class-0.26.tar.gz";
___
my $r = cpm_install "--cpanfile", "$cpanfile";
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
