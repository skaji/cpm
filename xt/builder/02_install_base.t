use v5.24;
use warnings;
use experimental qw(signatures);

use Cwd qw(getcwd);
use File::Temp qw(tempdir);
use Test::More;
use App::cpm::Builder::EUMM;
use App::cpm::Builder::MB;

my @cmd;
my $cwd = getcwd;
my $tmpdir = tempdir CLEANUP => 1;
chdir $tmpdir or die "chdir $tmpdir: $!";
END { chdir $cwd if defined $cwd }

{
    no warnings 'redefine';
    local *App::cpm::Builder::Base::run_configure = sub ($self, $ctx, $cmd, @) {
        @cmd = $cmd->@*;
        open my $fh, ">", $ctx->{configured_file} or die $!;
        close $fh;
        return 1;
    };

    subtest eumm_install_base_requires_use_install_command => sub () {
        my $ctx = { perl => $^X, make => "make", configured_file => "Makefile" };

        unlink "Makefile";
        App::cpm::Builder::EUMM->new(
            distfile => "A-1.0.tar.gz",
            install_base => "/tmp/local",
            use_install_command => 0,
            argv => [],
        )->configure($ctx, [], []);
        is_deeply \@cmd, [ $^X, "Makefile.PL" ];

        unlink "Makefile";
        App::cpm::Builder::EUMM->new(
            distfile => "A-1.0.tar.gz",
            install_base => "/tmp/local",
            use_install_command => 1,
            argv => [],
        )->configure($ctx, [], []);
        is_deeply \@cmd, [ $^X, "Makefile.PL", "INSTALL_BASE=/tmp/local" ];
    };

    subtest mb_install_base_requires_use_install_command => sub () {
        my $ctx = { perl => $^X, configured_file => "Build" };

        unlink "Build";
        App::cpm::Builder::MB->new(
            distfile => "A-1.0.tar.gz",
            install_base => "/tmp/local",
            use_install_command => 0,
            argv => [],
        )->configure($ctx, [], []);
        is_deeply \@cmd, [ $^X, "Build.PL" ];

        unlink "Build";
        App::cpm::Builder::MB->new(
            distfile => "A-1.0.tar.gz",
            install_base => "/tmp/local",
            use_install_command => 1,
            argv => [],
        )->configure($ctx, [], []);
        is_deeply \@cmd, [ $^X, "Build.PL", "--install_base", "/tmp/local" ];
    };
}

done_testing;
