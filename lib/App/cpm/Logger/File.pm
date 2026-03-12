package App::cpm::Logger::File;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Util 'WIN32';
use File::Temp ();
use POSIX ();

sub new ($class, $file = undef) {
    my $fh;
    if (WIN32) {
        require IO::File;
        $file ||= File::Temp::tmpnam();
    } elsif ($file) {
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

sub symlink_to ($self, $dest) {
    unlink $dest;
    if (!eval { symlink $self->file, $dest }) {
        $self->{file} = $dest;
    }
}

sub file ($self) { $self->{file} }

sub prefix ($self) {
    my $pid = $self->{pid} || $$;
    $self->{context} ? "$pid,$self->{context}" : $pid;
}

sub log {
    my ($self, @line) = @_;
    my $now = POSIX::strftime('%Y-%m-%dT%H:%M:%S', localtime);
    my $prefix = $self->prefix;
    local $self->{fh} = IO::File->new($self->{file}, 'a') if WIN32;
    for my $line (@line) {
        chomp $line;
        print { $self->{fh} } "$now,$prefix| $_\n" for split /\n/, $line;
    }
}

1;
