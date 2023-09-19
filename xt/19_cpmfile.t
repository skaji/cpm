use v5.16;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;
use Path::Tiny;

subtest basic => sub {
    my $cpmfile = Path::Tiny->tempfile;
    $cpmfile->spew(<<'EOF');
prereqs:
    runtime:
        requires:
            File::pushd: { version: '== 1.014' }
features:
    hoge:
        prereqs:
            runtime:
                requires:
                    common::sense: { version: '== 3.75' }
EOF

    my $r = cpm_install "--cpmfile", $cpmfile;
    like $r->err, qr/DONE install File-pushd-1.014/;
    unlike $r->err, qr/common-sense/;

    $r = cpm_install "--feature", "hoge", "--cpmfile", $cpmfile;
    like $r->err, qr/DONE install File-pushd-1.014/;
    like $r->err, qr/DONE install common-sense-3.75/;
};

subtest git => sub {
    my $cpmfile = Path::Tiny->tempfile;
    $cpmfile->spew(<<'___');
prereqs:
    runtime:
        requires:
            CPAN::Mirror::Tiny: { version: '< 0.05' }
            HTTP::Tinyish: { version: '== 0.06' }
            App::ChangeShebang: { git: 'https://github.com/skaji/change-shebang', ref: '0.05' }
            Try::Tiny: { url: 'https://cpan.metacpan.org/authors/id/E/ET/ETHER/Try-Tiny-0.30.tar.gz' }
___

    with_same_local {
        my $r = cpm_install "--cpmfile", "$cpmfile";
        is $r->exit, 0 or diag $r->err;
        like $r->err, qr/DONE install CPAN-Mirror-Tiny-0.04/;
        like $r->err, qr/DONE install HTTP-Tinyish-0.06/;
        like $r->err, qr{DONE install https://github.com/skaji/change-shebang};
        like $r->err, qr/DONE install Try-Tiny-0.30/;
        like $r->log, qr/Resolved CPAN::Mirror::Tiny.*from MetaDB/;
        like $r->log, qr/Resolved HTTP::Tinyish.*from MetaDB/;
        like $r->log, qr/Resolved App::ChangeShebang.*from Custom/;
        like $r->log, qr/Resolved Try::Tiny.*from Custom/;
        note $r->err;
        my $file = path($r->local, "lib/perl5/App/ChangeShebang.pm");
        my $content = $file->slurp_raw;
        my $want = q{our $VERSION = '0.05';};
        like $content, qr{\Q$want};

        # 2nd time; only install git
        $r = cpm_install "--cpmfile", "$cpmfile";
        is $r->exit, 0;
        like $r->err, qr{DONE install https://github.com/skaji/change-shebang};
        unlike $r->err, qr/CPAN-Mirror-Tiny/;
        unlike $r->err, qr/HTTP-Tinyish/;
        unlike $r->err, qr/Try-Tiny/;
    };
};

subtest dist_url => sub {
    my $cpmfile = Path::Tiny->tempfile;
    $cpmfile->spew(<<'___');
prereqs:
    runtime:
        requires:
            Path::Class: { version: '0.26', dist: "KWILLIAMS/Path-Class-0.26.tar.gz" }
            Hash::MultiValue: { dist: "MIYAGAWA/Hash-MultiValue-0.15.tar.gz" }
            Cookie::Baker: { dist: "KAZEBURO/Cookie-Baker-0.08.tar.gz", mirror: "http://www.cpan.org/" }
            Try::Tiny: { version: '0.28', url: "http://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz" }
___

    with_same_local {
        my $r = cpm_install "--cpmfile", "$cpmfile";
        is $r->exit, 0;

        like $r->log, qr/Hash-MultiValue-0\.15\| Successfully installed distribution/;
        like $r->log, qr/Path-Class-0\.26\| Successfully installed distribution/;
        like $r->log, qr/Cookie-Baker-0\.08\| Successfully installed distribution/;
        like $r->log, qr!Fetching \Qhttp://www.cpan.org/authors/id/K/KA/KAZEBURO/Cookie-Baker-0.08.tar.gz\E!;
        like $r->log, qr/Try-Tiny-0\.28\| Successfully installed distribution/;
        like $r->log, qr!Fetching \Qhttp://backpan.perl.org/authors/id/E/ET/ETHER/Try-Tiny-0.28.tar.gz\E!;

        $r = cpm_install "--cpmfile", "$cpmfile";
        is $r->exit, 0;
        like $r->err, qr/All requirements are satisfied/;
    };
};

done_testing;
