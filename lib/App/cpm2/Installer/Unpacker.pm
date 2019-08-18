package App::cpm2::Installer::Unpacker;
use strict;
use warnings;

use File::Path ();
use File::Spec;
use File::Temp ();
use IPC::Run3 ();
use File::Basename ();

sub new {
    my ($class, %argv) = @_;
    my $home = $argv{home};
    bless { home => $home }, $class;
}

sub _directory {
    my ($self, $file) = @_;
    my $base = File::Basename::basename $file;
    $base =~ s{\.(?:\.tar\.gz|tgz|zip)$}{};
    File::Temp::tempdir("$base-XXXXXXXX", DIR => $self->{home}, CLEANUP => 0);
}

sub unpack {
    my ($self, $file) = @_;

    my $directory = $self->_directory($file);
    my @cmd = ('tar', 'xf', $file, '-C', $directory, "--strip-components", 1);
    my $out;
    IPC::Run3::run3 \@cmd, undef, \$out, \$out;
    return $directory if $? == 0;
    return (undef, $out);
}

1;
