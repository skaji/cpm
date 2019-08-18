use strict;
use warnings;
use Test::More;
use File::Find ();

my @file; File::Find::find(sub { /\.pm$/ and push @file, $File::Find::name }, "lib");

for my $file (@file) {
    my $package = $file;
    $package =~ s{^lib/}{};
    $package =~ s{/}{::}g;
    $package =~ s{\.pm}{};
    use_ok $package;
}

done_testing;
