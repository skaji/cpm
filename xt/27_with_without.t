use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny ();

my $cpanfile = Path::Tiny->tempfile; $cpanfile->spew(<<'___');
on test => sub {
    recommends 'Process::Status';
    suggests 'App::ChangeShebang';
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

subtest 'normal' => sub {
    my $r = cpm_install '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like $r->err, qr/All requirements are satisfied/;
};

subtest 'develop' => sub {
    my $r = cpm_install '--with-develop', '--test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->err, qr/DONE install Process-Status/;
    unlike $r->err, qr/DONE install App-ChangeShebang/;
    like   $r->err, qr/DONE install Parallel-Pipes/;
    unlike $r->err, qr/DONE install File-pushd/;
    unlike $r->err, qr/DONE install Try-Tiny/;
    unlike $r->err, qr/DONE install Devel-CheckBin/;
};

subtest 'recommends' => sub {
    my $r = cpm_install '--with-recommends', '--test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->err, qr/DONE install Process-Status/;
    unlike $r->err, qr/DONE install App-ChangeShebang/;
    unlike $r->err, qr/DONE install Parallel-Pipes/;
    unlike $r->err, qr/DONE install File-pushd/;
    unlike $r->err, qr/DONE install Try-Tiny/;
    unlike $r->err, qr/DONE install Devel-CheckBin/;
};

subtest 'recommends --no-test' => sub {
    my $r = cpm_install '--with-recommends', '--no-test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->err, qr/DONE install Process-Status/;
    unlike $r->err, qr/DONE install App-ChangeShebang/;
    unlike $r->err, qr/DONE install Parallel-Pipes/;
    unlike $r->err, qr/DONE install File-pushd/;
    unlike $r->err, qr/DONE install Try-Tiny/;
    unlike $r->err, qr/DONE install Devel-CheckBin/;
};

subtest 'suggests' => sub {
    my $r = cpm_install '--with-suggests', '--test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->err, qr/DONE install Process-Status/;
    like   $r->err, qr/DONE install App-ChangeShebang/;
    unlike $r->err, qr/DONE install Parallel-Pipes/;
    unlike $r->err, qr/DONE install File-pushd/;
    unlike $r->err, qr/DONE install Try-Tiny/;
    unlike $r->err, qr/DONE install Devel-CheckBin/;
};

subtest 'mix1' => sub {
    my $r = cpm_install '--with-configure', '--without-test', '--with-recommends', '--test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    unlike $r->err, qr/DONE install Process-Status/;
    unlike $r->err, qr/DONE install App-ChangeShebang/;
    unlike $r->err, qr/DONE install Parallel-Pipes/;
    unlike $r->err, qr/DONE install File-pushd/;
    unlike $r->err, qr/DONE install Try-Tiny/;
    like   $r->err, qr/DONE install Devel-CheckBin/;
};

subtest 'mix2' => sub {
    my $r = cpm_install '--with-develop', '--with-recommends', '--with-suggests', '--test', '--cpanfile', $cpanfile;
    is $r->exit, 0;
    like   $r->err, qr/DONE install Process-Status/;
    like   $r->err, qr/DONE install App-ChangeShebang/;
    like   $r->err, qr/DONE install Parallel-Pipes/;
    like   $r->err, qr/DONE install File-pushd/;
    like   $r->err, qr/DONE install Try-Tiny/;
    unlike $r->err, qr/DONE install Devel-CheckBin/;
};

done_testing;
