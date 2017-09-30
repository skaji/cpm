use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny ();
use App::cpm::version;

my $cpanfile = Path::Tiny->tempfile; $cpanfile->spew(<<'___');
requires 'File::pushd';

feature foo => sub {
    requires 'Data::Section::Simple';
    requires 'File::pushd', '< 1.014';
};
___

my ($r, $v);
my $V = qr/[0-9\._]+/;

$r = cpm_install '--cpanfile', $cpanfile;
is $r->exit, 0;
($v) = $r->err =~ /DONE install File-pushd-($V)/;
$v = App::cpm::version->parse($v)->numify;
ok $v >= 1.014;
note $r->err;

$r = cpm_install '--cpanfile', $cpanfile, '--feature', 'foo';
is $r->exit, 0;
like $r->err, qr/DONE install Data-Section-Simple-/;
($v) = $r->err =~ /DONE install File-pushd-($V)/;
$v = App::cpm::version->parse($v)->numify;
ok $v < 1.014;
note $r->err;

done_testing;
