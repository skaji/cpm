use v5.16;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;
use Path::Tiny;

subtest basic => sub {
    my $metafile = Path::Tiny->tempfile;
    $metafile->spew(<<'EOF');
{
  "name": "_",
  "version": "1",
  "dynamic_config": 0,
  "meta-spec": {
    "version": 2
  },
  "x_static_install": 1,
  "prereqs": {
    "runtime": {
      "requires": {
        "File::pushd": "0"
      }
    }
  },
  "optional_features": {
    "hoge": {
      "prereqs": {
        "runtime": {
          "requires": {
            "common::sense": "0"
          }
        }
      }
    }
  }
}
EOF
    my $r = cpm_install "--metafile", $metafile;
    like $r->err, qr/DONE install File-pushd-/;
    unlike $r->err, qr/common-sense/;

    $r = cpm_install "--feature", "hoge", "--metafile", $metafile;
    like $r->err, qr/DONE install File-pushd-/;
    like $r->err, qr/DONE install common-sense-/;
};

done_testing;
