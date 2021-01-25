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
EOF

    my $r = cpm_install "--cpmfile", $cpmfile;
    like $r->err, qr/DONE install File-pushd-1.014/;
};

done_testing;
