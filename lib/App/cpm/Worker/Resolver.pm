package App::cpm::Worker::Resolver;
use strict;
use warnings;
our $VERSION = '0.214';
use File::Temp ();
use App::cpm::Logger::File;

sub new {
    my ($class, %option) = @_;
    my $logger = $option{logger};
    if (!$logger) {
        (undef, my $file) = File::Temp::tempfile(UNLINK => 1);
        $logger = App::cpm::Logger::File->new($file);
    }
    bless { impl => $option{impl}, logger => $logger }, $class;
}

sub work {
    my ($self, $job) = @_;

    local $self->{logger}->{context} = $job->{package};
    if (my $result = $self->{impl}->resolve($job)) {
        $result->{ok} = 1;
        $result->{uri} = [$result->{uri}] unless ref $result->{uri};
        my $msg = sprintf "Resolved %s (%s) -> %s", $job->{package}, $job->{version} || 0,
            $result->{uri}[0] . ($result->{from} ? " from $result->{from}" : "");
        $self->{logger}->log($msg);
        return $result;
    } else {
        my $msg = sprintf "Failed to resolve %s", $job->{package};
        $self->{logger}->log($msg);
        return { ok => 0 };
    }
}

1;
