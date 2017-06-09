package App::cpm::Logger::File;
use strict;
use warnings;
use POSIX ();
use File::Temp ();
our $VERSION = '0.306';

sub new {
    my ($class, $file) = @_;
    my $fh;
    if ($file) {
        open $fh, ">>:unix", $file or die "$file: $!";
    } else {
        ($fh, $file) = File::Temp::tempfile(UNLINK => 1);
    }
    bless {
        context => '',
        fh => $fh,
        file => $file,
        pid => '',
    }, $class;
}

sub symlink_to {
    return unless eval { symlink "", ""; 1 };
    my ($self, $dest) = @_;
    unlink $dest;
    symlink $self->file, $dest;
}

sub file {
    shift->{file};
}

sub prefix {
    my $self = shift;
    my $pid = $self->{pid} || $$;
    $self->{context} ? "$pid,$self->{context}" : $pid;
}

sub log {
    my ($self, @line) = @_;
    my $now = POSIX::strftime('%FT%T', localtime);
    my $prefix = $self->prefix;
    for my $line (@line) {
        chomp $line;
        print { $self->{fh} } "$now,$prefix| $_\n" for split /\n/, $line;
    }
}

sub log_with_fh {
    my ($self, $fh) = @_;
    my $prefix = $self->prefix;
    while (my $line = <$fh>) {
        chomp $line;
        print { $self->{fh} } "@{[POSIX::strftime('%FT%T', localtime)]},$prefix| $line\n";
    }
}

1;
