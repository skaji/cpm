use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;
use Path::Tiny;
use File::pushd 'tempd';

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

subtest dynamic_config => sub {
    my $guard = tempd;
    Path::Tiny->new('META.json')->spew(<<'EOF');
{
  "name": "_",
  "version": "1",
  "dynamic_config": 1,
  "meta-spec": {
    "version": 2
  },
  "prereqs": {
    "runtime": {
      "requires": {
        "File::pushd": "0"
      }
    }
  }
}
EOF
    my $r = cpm_install;
    isnt $r->exit, 0;
    unlike $r->err, qr/DONE install File-pushd-/;

    Path::Tiny->new('META.json')->spew(<<'EOF');
{
  "name": "_",
  "version": "1",
  "dynamic_config": 0,
  "meta-spec": {
    "version": 2
  },
  "prereqs": {
    "runtime": {
      "requires": {
        "File::pushd": "0"
      }
    }
  }
}
EOF
    $r = cpm_install;
    is $r->exit, 0;
    like $r->err, qr/DONE install File-pushd-/;
};

done_testing;
