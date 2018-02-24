use strict;
use warnings;
use utf8;
use Test::More;
use lib "xt/lib";
use CLI;

use HTTP::Tinyish;
use CPAN::Meta::YAML;

my $latest = do {
    my $url = 'http://cpanmetadb.plackperl.org/v1.0/package/App::ChangeShebang';
    my $res = HTTP::Tinyish->new->get($url);
    die "$res->{status} $res->{reason}, $url\n" unless $res->{success};
    my $yaml = CPAN::Meta::YAML->read_string($res->{content});
    $yaml->[0]{version};
};

note "latest App::ChangeShebang is $latest";

# test for up to date
with_same_local {
    my $r = cpm_install "App::ChangeShebang\@$latest";
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-$latest/;

    $r = cpm_install 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App::ChangeShebang is up to date/;

    $r = cpm_install 'App::ChangeShebang@0.05';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-0.05/;

    $r = cpm_install 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-$latest/;
};

# test for reinstall
with_same_local {
    my $r = cpm_install 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-/;

    $r = cpm_install '--reinstall', 'App::ChangeShebang';
    is $r->exit, 0;
    like $r->err, qr/DONE install App-ChangeShebang-/;
};

done_testing;
