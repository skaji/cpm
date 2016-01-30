package xt::CLI;
use strict;
use warnings;
use utf8;
use Capture::Tiny 'capture';
use File::Temp 'tempdir';
use Exporter 'import';
use FindBin '$Bin';
use Cwd 'abs_path';
our @EXPORT = qw(cpm_install with_same_local);

my $base = abs_path("$Bin/..");

my $TEMPDIR = tempdir CLEANUP => 1;

{
    package Result;
    no strict 'refs';
    sub new {
        my $class = shift;
        bless {@_}, $class;
    }
    for my $attr (qw(local out err exit)) {
        *$attr = sub { shift->{$attr} };
    }
    sub success { shift->exit == 0 }
}

our $_LOCAL;

sub with_same_local (&) {
    my $sub = shift;
    local $_LOCAL = tempdir DIR => $TEMPDIR;
    $sub->();
}

sub cpm_install {
    my @argv = @_;
    my $local = $_LOCAL || tempdir DIR => $TEMPDIR;
    my ($out, $err, $exit) = capture {
        system $^X, "-I$base/lib", "$base/script/cpm", "install", "-L", $local, @argv;
    };
    Result->new(local => $local, out => $out, err => $err, exit => $exit);
}


1;
