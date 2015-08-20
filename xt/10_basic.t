use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;

subtest basic => sub {
    my $r = cpm_install "App::FatPacker";
    like $r->err, qr/^DONE install App-FatPacker/;
    like $r->err, qr/1 distribution installed/;
    ok -f $r->local . "/bin/fatpack";
};

subtest same => sub {
    with_same_local {
        my $r1 = cpm_install "App::FatPacker";
        my $r2 = cpm_install "App::FatPacker";
        like $r1->err, qr/^DONE install App-FatPacker/;
        like $r1->err, qr/1 distribution installed/;
        like $r2->err, qr/^DONE install App::FatPacker is up to date/;
        like $r2->err, qr/0 distribution installed/;
    };
};

done_testing;
