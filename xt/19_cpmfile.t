use strict;
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

done_testing;
