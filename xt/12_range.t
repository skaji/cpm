use strict;
use warnings;
use Test::More;
use lib ".";
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
    $cpanfile->spew(qq(requires "Distribution::Metadata", "== 0.04";\n));
    my $r = cpm_install "--cpanfile", $cpanfile->stringify;
    is $r->exit, 0;
    note $r->err;
};

done_testing;
