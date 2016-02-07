use strict;
use warnings;
use Test::More;
use xt::CLI;
use Path::Tiny;

subtest ok => sub {
    my $cpanfile = Path::Tiny->tempfile;
    $cpanfile->spew(qq(requires "Distribution::Metadata", ">= 0.01, < 3.00";\n));
    my $r = cpm_install "--cpanfile", $cpanfile->stringify;
    is $r->exit, 0;
};

subtest ng => sub {
    my $cpanfile = Path::Tiny->tempfile;

    # I know if we use history API of cpanmetadb,
    # we may resolve Distribution::Metadata with version == 0.04.
    # But, it is difficult to handle version range "correctly",
    # and cpm should be merged into cpanminus soon.
    # So I leave it open.
    $cpanfile->spew(qq(requires "Distribution::Metadata", "== 0.04";\n));
    my $r = cpm_install "--cpanfile", $cpanfile->stringify;
    isnt $r->exit, 0;
    note $r->err;
};

done_testing;
