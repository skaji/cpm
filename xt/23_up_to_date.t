use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;

# XXX assume the latest version of App-ChangeShebang is 0.06

with_same_local {
    my $r = cpm_install 'App::ChangeShebang@0.06';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-0.06/;

    $r = cpm_install 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App::ChangeShebang is up to date/;

    $r = cpm_install 'App::ChangeShebang@0.05';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-0.05/;

    $r = cpm_install 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-0.06/;
};

done_testing;
