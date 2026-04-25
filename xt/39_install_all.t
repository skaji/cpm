use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use File::Spec;
use Test::More;
use lib "xt/lib";
use CLI;
use Path::Tiny;

subtest direct_target => sub () {
    my $installed = sub ($local, $path) {
        -f File::Spec->catfile($local, "lib", "perl5", split "/", $path);
    };

    my $r = cpm_install "--test", "Data::Section::Simple";
    is $r->exit, 0;
    ok $installed->($r->local, "Data/Section/Simple.pm");
    ok !$installed->($r->local, "Test/Requires.pm");

    $r = cpm_install "--test", "--install-all", "Data::Section::Simple";
    is $r->exit, 0;
    ok $installed->($r->local, "Data/Section/Simple.pm");
    ok $installed->($r->local, "Test/Requires.pm");
};

subtest cpmfile => sub () {
    my $cpmfile = Path::Tiny->tempfile;
    $cpmfile->spew(<<'EOF');
prereqs:
    runtime:
        requires:
            CPAN::Test::Dummy::Perl5::ModuleBuild: { version: '== 0.001' }
    test:
        requires:
            File::pushd: { version: 0 }
EOF

    my $installed = sub ($local, $path) {
        -f path($local, "lib", "perl5", split "/", $path);
    };

    my $r = cpm_install "--cpmfile", $cpmfile;
    is $r->exit, 0;
    ok $installed->($r->local, "CPAN/Test/Dummy/Perl5/ModuleBuild.pm");
    ok $installed->($r->local, "File/pushd.pm");
    ok !$installed->($r->local, "Module/Build.pm");

    $r = cpm_install "--install-all", "--cpmfile", $cpmfile;
    is $r->exit, 0;
    ok $installed->($r->local, "CPAN/Test/Dummy/Perl5/ModuleBuild.pm");
    ok $installed->($r->local, "File/pushd.pm");
    ok $installed->($r->local, "Module/Build.pm");
};

subtest prebuilt => sub () {
    my $installed = sub ($local, $path) {
        -f path($local, "lib", "perl5", split "/", $path);
    };

    with_same_home {
        cpm_install "--prebuilt", "--test", "Data::Section::Simple";

        my $r = cpm_install "--prebuilt", "--test", "--install-all", "Data::Section::Simple";
        is $r->exit, 0;
        ok $installed->($r->local, "Data/Section/Simple.pm");
        ok $installed->($r->local, "Test/Requires.pm");
    };
};

done_testing;
