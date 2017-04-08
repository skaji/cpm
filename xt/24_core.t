use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;
use Module::Metadata;
use Config;
use File::Spec;

sub has_DB_File {
    my @inc = @_;
    my @core = (
        (grep {$_} @Config{qw(vendorarch vendorlibexp)}),
        @Config{qw(archlibexp privlibexp)},
    );
    my $info = Module::Metadata->new_from_module('DB_File', inc => [@core, @inc]);
    $info ? 1 : 0;
}

if (has_DB_File()) {
    note "Already has DB_File";
} else {
    note "Does not have DB_File";
}

my $cpanfile = Path::Tiny->tempfile;
$cpanfile->spew("requires 'DB_File';\n");

my $r = cpm_install "--cpanfile", "$cpanfile";
note $r->err;
is $r->exit, 0 or diag $r->err;

my @lib = (
    File::Spec->catdir($r->local, "lib/perl5"),
    File::Spec->catdir($r->local, "lib/perl5/$Config{archname}"),
);

ok has_DB_File(@lib);

done_testing;
