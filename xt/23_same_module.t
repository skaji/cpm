use strict;
use warnings;
use utf8;
use Test::More;
use lib "xt/lib";
use CLI;

use HTTP::Tinyish;
use CPAN::Meta::YAML;
use Path::Tiny ();

my $latest = do {
    my $url = 'https://cpanmetadb.plackperl.org/v1.0/package/App::ChangeShebang';
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

with_same_local {
    my $r = cpm_install 'App::ChangeShebang@0.06';
    is $r->exit, 0;

    # if version_range is specified,
    # we install App::ChangeShebang only if latest version does not satisfy the version_range
    my $version_range = '> 0.05';
    $r = cpm_install "App::ChangeShebang~$version_range";
    is $r->exit, 0;
    like $r->err, qr/\QDONE install App::ChangeShebang, you already have 0.06/;

    # if current local version == A, and resolved **latest** version == B, and A > B,
    # then we do not install version B
    my $index = Path::Tiny->tempfile;
    $index->append("test index\n\n");
    $index->append("App::ChangeShebang  0.05  S/SK/SKAJI/App-ChangeShebang-0.05.tar.gz\n");
    $r = cpm_install "-r", "02package,$index,https://cpan.metacpan.org", "App::ChangeShebang";
    is $r->exit, 0;
    like $r->err, qr/\QDONE install App::ChangeShebang, you already have 0.06/;

    my $cpanfile = Path::Tiny->tempfile;
    $cpanfile->append("requires 'App::ChangeShebang', '0.05';\n");
    $r = cpm_install "--cpanfile", $cpanfile;
    is $r->exit, 0;
    like $r->err, qr/All requirements are satisfied/;
};

done_testing;
