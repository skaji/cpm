package App::cpm2::Unpacker;
use strict;
use warnings;

use File::Path ();
use File::Spec;
use File::Temp ();
use IPC::Run3 ();

sub new {
    my $class = shift;
    my $base = File::Spec->catdir($ENV{HOME}, '.cpm2', 'work');
    my $time = time;
    bless { base => $base, time => $time }, $class;
}

sub _directory {
    my $self = shift;
    File::Temp::tempdir("$self->{time}-XXXXX", DIR => $self->{base}, CLEANUP => 0);
}

sub unpack {
    my ($self, $file) = @_;

    my $directory = $self->_directory;
    my @cmd = ('tar', 'xf', $file, '-C', $directory);
    my $out;
    IPC::Run3::run3 \@cmd, undef, \$out, \$out;
    my $exit = $?;
    if ($exit == 0 and opendir my ($dh), $directory) {
        my @found =
            grep { -d $_ }
            map  { File::Spec->catdir($directory, $_) }
            grep { $_ ne "." && $_ ne ".." }
            readdir $dh;
        return $found[0] if @found == 1;
    }
    return (undef, $out);
}

1;
