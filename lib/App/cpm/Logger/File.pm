package App::cpm::Logger::File;
use strict;
use warnings;
use POSIX ();
our $VERSION = '0.291';

sub new {
    my ($class, $file) = @_;
    open my $fh, ">>:unix", $file or die "$file: $!";
    bless {
        context => '',
        fh => $fh,
        file => $file,
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

sub context {
    my $self = shift;
    $self->{context} ? ",$self->{context}" : "";
}

sub log {
    my $self = shift;
    my $now = POSIX::strftime('%FT%T', localtime);
    my $context = $self->context;
    for my $line (@_) {
        chomp $line;
        print { $self->{fh} } "$now,${$}$context| $_\n" for split /\n/, $line;
    }
}

sub log_with_fh {
    my ($self, $fh) = @_;
    my $context = $self->context;
    while (my $line = <$fh>) {
        chomp $line;
        print { $self->{fh} } "@{[POSIX::strftime('%FT%T', localtime)]},${$}$context| $line\n";
    }
}

1;
