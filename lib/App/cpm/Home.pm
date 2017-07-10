package App::cpm::Home;
use strict;
use warnings;
use File::Spec;
use constant WIN32 => $^O eq 'MSWin32';

our $HOME;

sub dir {
    my $class = shift;
    return $HOME ||= $class->determine_home;
}

sub determine_home { # taken from Menlo
    my $class = shift;

    my $homedir = $ENV{HOME}
      || eval { require File::HomeDir; File::HomeDir->my_home }
      || join('', @ENV{qw(HOMEDRIVE HOMEPATH)}); # Win32

    if (WIN32) {
        require Win32; # no fatpack
        $homedir = Win32::GetShortPathName($homedir);
    }

    return "$homedir/.perl-cpm";
}

1;
