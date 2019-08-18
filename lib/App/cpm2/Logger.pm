package App::cpm2::Logger;
use strict;
use warnings;
use POSIX ();

sub new {
    my ($class, $file) = @_;
    open my $fh, ">>:unix", $file or die;
    bless { context => "global", fh => $fh }, $class;
}

sub log {
    my ($self, @line) = @_;
    my $time = POSIX::strftime "%Y-%m-%d %H:%M:%S", localtime;
    my $header = join ",", grep length, $time, $$, $self->{context};
    for my $line (@line) {
        chomp $line;
        print "$header| $_\n" for split /\n/, $line;
    }
}


1;
