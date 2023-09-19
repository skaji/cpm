use v5.16;
use warnings;
use Test::More;

use App::cpm::Installer::Unpacker;
use File::Basename 'basename';
use File::Copy 'copy';
use File::Spec::Functions 'catfile';
use File::Temp 'tempdir';
use File::pushd qw(tempd pushd);

my $store = tempdir CLEANUP => 1;
{
    my $guard = pushd $store;
    !system "curl", "-fsSLO", "https://cpan.metacpan.org/authors/id/C/CJ/CJOHNSTON/Win32-SystemInfo-0.11.zip" or die;
    !system "curl", "-fsSLO", "https://cpan.metacpan.org/authors/id/J/JJ/JJONES/Finance-OFX-Parse-Simple-0.07.zip" or die;

    !system "curl", "-fsSL", "-o", "master.tar.gz", "https://github.com/skaji/Archive-Unpack/archive/master.tar.gz" or die;
    !system "curl", "-fsSLO", "https://cpan.metacpan.org/authors/id/S/SK/SKAJI/CPAN-Flatten-0.01.tar.gz" or die;
    !system "curl", "-fsSLO", "https://ftp.gnu.org/gnu/m4/m4-1.4.3.tar.bz2" or die;
}

my $unpacker = App::cpm::Installer::Unpacker->new(_init_all => 1);
note explain $unpacker->describe;

my $test = sub {
    my $method = shift;
    subtest $method => sub {
        my $guard = tempd;
        if ($method !~ /unzip/) {
            my ($root, $err) = $unpacker->$method("__bad__.tar.gz");
            ok !$root;
            ok $err;
            note $err;

            ($root, $err) = $unpacker->$method(catfile($store, "CPAN-Flatten-0.01.tar.gz"));
            is $root, "CPAN-Flatten-0.01" or diag $err;
            ($root, $err) = $unpacker->$method(catfile($store, "m4-1.4.3.tar.bz2"));
            is $root, "m4-1.4.3" or diag $err;
            ($root, $err) = $unpacker->$method(catfile($store, "master.tar.gz"));
            is $root, "Archive-Unpack-master" or diag $err;
        }

        if ($method !~ /untar/) {
            my ($root, $err) = $unpacker->$method("__bad__.zip");
            ok !$root;
            ok $err;
            note $err;

            ($root, $err) = $unpacker->$method(catfile($store, "Win32-SystemInfo-0.11.zip"));
            is $root, "Win32-SystemInfo-0.11" or diag $err;
            ($root, $err) = $unpacker->$method(catfile($store, "Finance-OFX-Parse-Simple-0.07.zip"));
            is $root, "Finance--OFX--Parse--Simple-master" or diag $err;
        }
    };
};

my @method = qw(unpack _unzip _unzip_module _untar_bad _untar_module);
push @method, "_untar" if $^O ne 'MSWin32';
$test->($_) for @method;

opendir my ($dh), $store or die;
my @entry = grep { !/^\.\.?$/ } readdir $dh;
close $dh;
is @entry, 5;

done_testing;
