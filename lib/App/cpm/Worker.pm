package App::cpm::Worker;
use strict;
use warnings;
use utf8;

use App::cpm::Worker::Installer;
use App::cpm::Worker::Resolver;
use App::cpm::Logger;
use CPAN::DistnameInfo;
use JSON::PP qw(encode_json decode_json);
use Time::HiRes qw(gettimeofday tv_interval);

sub new {
    my ($class, %option) = @_;
    my $installer = App::cpm::Worker::Installer->new(%option);
    my $resolver  = App::cpm::Worker::Resolver->new(%option);
    bless { %option, installer => $installer, resolver => $resolver }, $class;
}

sub run_loop {
    my $self = shift;

    my $read_fh = $self->{read_fh};
    while (my $raw = <$read_fh>) {
        my $job = eval { decode_json $raw } or last;
        my $type = $job->{type} || "(undef)";
        my $result;
        my $start = $self->{verbose} ? [gettimeofday] : undef;
        if (grep {$type eq $_} qw(fetch configure install)) {
            $result = eval { $self->{installer}->work($job) };
            warn $@ if $@;
        } elsif ($type eq "resolve") {
            $result = eval { $self->{resolver}->work($job) };
            warn $@ if $@;
        } else {
            die "Unknown type: $type\n";
        }
        my $elapsed = $start ? tv_interval($start) : undef;
        $result ||= { ok => 0 };
        $job = +{ %$job, %$result };
        $self->info($job, $elapsed);
        my $res = encode_json $job;
        syswrite $self->{write_fh}, "$res\n";
    }
}

sub info {
    my ($self, $job, $elapsed) = @_;
    my $type = $job->{type};
    return if !$App::cpm::Logger::VERBOSE && $type ne "install";
    my $distvname = CPAN::DistnameInfo->new($job->{distfile})->distvname || $job->{distfile};
    my $message;
    if ($type eq "resolve") {
        $message = $job->{package} . ($job->{ok} ? " -> $distvname" : "");
    } else {
        $message = $distvname;
    }
    $elapsed = defined $elapsed ? sprintf "(%.3fsec) ", $elapsed : "";

    App::cpm::Logger->log(
        type => $type,
        result => $job->{ok} ? "DONE" : "FAIL",
        message => "$elapsed$message",
    );
}

1;
