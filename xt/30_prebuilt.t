use strict;
use warnings;
use Test::More;
use Config;
use File::Spec;
use Path::Tiny 'path';
use lib "xt/lib";
use CLI;

plan skip_all => 'only for perl 5.12+' if $] < 5.012;

with_same_home {
    my $r = cpm_install "--prebuilt", "App::ChangeShebang", "File::pushd";
    is $r->exit, 0;
    my ($builds) = glob $r->home . "/builds/$Config{version}-$Config{archname}-*";
    my @File_pushd = glob "$builds/DAGOLDEN/File-pushd-*";
    my @ChangeShebang = glob "$builds/SKAJI/App-ChangeShebang-*";
    is @File_pushd, 1;
    is @ChangeShebang, 1;

    $r = cpm_install "--prebuilt", "App::ChangeShebang", "File::pushd", "Parallel::Pipes";
    is $r->exit, 0;
    my $v = qr/v?[\d\.]+/;
    like $r->err, qr/^DONE install App-ChangeShebang-$v \(using prebuilt\)$/m;
    like $r->err, qr/^DONE install File-pushd-$v \(using prebuilt\)$/m;
    like $r->err, qr/^DONE install Parallel-Pipes-$v$/m;
    note $r->err;

    my @Parallel_Pipes = glob "$builds/SKAJI/Parallel-Pipes-*";
    is @Parallel_Pipes, 1;

    my $packlist1 = path($r->local, "lib/perl5/$Config{archname}/auto/App/ChangeShebang/.packlist");
    my $packlist2 = path($r->local, "lib/perl5/$Config{archname}/auto/File/pushd/.packlist");
    my $packlist3 = path($r->local, "lib/perl5/$Config{archname}/auto/Parallel/Pipes/.packlist");
    ok $_->is_file for $packlist1, $packlist2, $packlist3;

    my @line = $packlist1->lines({chomp => 1});
    my $expect = File::Spec->catfile($r->local, "bin/change-shebang");
    ok !!grep { $_ eq $expect } @line;
};

with_same_home {
    cpm_install "--prebuilt", "XML::SAX";
    my $r = cpm_install "--prebuilt", "XML::SAX";
    is $r->exit, 0;
    my $v = qr/v?[\d\.]+/;
    unlike $r->err, qr/XML-SAX-$v \(using prebuilt\)/i;
    note $r->err;
};

done_testing;
