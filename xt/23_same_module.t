use v5.16;
use warnings;
use utf8;
use Test::More;
use lib "xt/lib";
use CLI;

use HTTP::Tinyish;
use CPAN::Meta::YAML;
use Path::Tiny ();

my $latest = do {
    my $url = 'https://cpanmetadb.plackperl.org/v1.0/package/Parallel::Pipes';
    my $res = HTTP::Tinyish->new->get($url);
    die "$res->{status} $res->{reason}, $url\n" unless $res->{success};
    my $yaml = CPAN::Meta::YAML->read_string($res->{content});
    $yaml->[0]{version};
};

note "latest Parallel::Pipes is $latest";

# test for up to date
with_same_local {
    my $r = cpm_install "Parallel::Pipes\@$latest";
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel-Pipes-$latest/;

    $r = cpm_install 'Parallel::Pipes';
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel::Pipes is up to date/;

    $r = cpm_install 'Parallel::Pipes@0.102';
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel-Pipes-0.102/;

    $r = cpm_install 'Parallel::Pipes';
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel-Pipes-$latest/;
};

# test for reinstall
with_same_local {
    my $r = cpm_install 'Parallel::Pipes';
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel-Pipes-/;

    $r = cpm_install '--reinstall', 'Parallel::Pipes';
    is $r->exit, 0;
    like $r->err, qr/DONE install Parallel-Pipes-/;
};

with_same_local {
    my $r = cpm_install 'Parallel::Pipes@0.102';
    is $r->exit, 0;

    # if version_range is specified,
    # we install Parallel::Pipes only if latest version does not satisfy the version_range
    my $version_range = '> 0.100';
    $r = cpm_install "Parallel::Pipes~$version_range";
    is $r->exit, 0;
    like $r->err, qr/\QDONE install Parallel::Pipes, you already have 0.102/;

    # if current local version == A, and resolved **latest** version == B, and A > B,
    # then we do not install version B
    my $index = Path::Tiny->tempfile;
    $index->append("test index\n\n");
    $index->append("Parallel::Pipes  0.101  S/SK/SKAJI/Parallel-Pipes-0.101.tar.gz\n");
    $r = cpm_install "-r", "02package,$index,https://cpan.metacpan.org", "Parallel::Pipes";
    is $r->exit, 0;
    like $r->err, qr/\QDONE install Parallel::Pipes, you already have 0.102/;

    my $cpanfile = Path::Tiny->tempfile;
    $cpanfile->append("requires 'Parallel::Pipes', '0.101';\n");
    $r = cpm_install "--cpanfile", $cpanfile;
    is $r->exit, 0;
    like $r->err, qr/All requirements are satisfied/;
};

done_testing;
