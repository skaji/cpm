#!/usr/bin/env perl
use strict;
use warnings;

use Digest::MD5 ();
use File::Find ();
use Getopt::Long ();

Getopt::Long::GetOptions
    "file=s" => \my $file,
    "id=s"   => \my $id,
or exit 1;

my @cmd = @ARGV;

my ($take, $all) = split /\//, $id;

my @taken;
for my $file (sort glob $file) {
    my $digest = hex unpack "H8", Digest::MD5::md5($file);
    if ($digest % $all == $take) {
        push @taken, $file;
    }
}

warn "@cmd @taken\n";
system @cmd, @taken;
exit $?;
