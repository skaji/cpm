package Acme::CPAN::Installer::Worker;
use strict;
use warnings;
use utf8;

use Acme::CPAN::Installer::Worker::Installer;
use Acme::CPAN::Installer::Worker::Resolver;
use CPAN::DistnameInfo;
use JSON::PP qw(encode_json decode_json);

sub new {
    my ($class, %option) = @_;
    my $installer = Acme::CPAN::Installer::Worker::Installer->new(%option);
    my $resolver  = Acme::CPAN::Installer::Worker::Resolver->new(%option);
    bless { %option, installer => $installer, resolver => $resolver }, $class;
}

sub run_loop {
    my $self = shift;

    my $read_fh = $self->{read_fh};
    while (my $raw = <$read_fh>) {
        my $job = eval { decode_json $raw } or last;
        my $type = $job->{type} || "(undef)";
        my $result;
        if ($type eq "install") {
            $result = eval { $self->{installer}->work($job) };
        } elsif ($type eq "resolve") {
            $result = eval { $self->{resolver}->work($job) };
        } else {
            warn "Unknown type: $type\n";
        }
        $job = +{ %$job, result => $result };
        $self->info($job);
        my $res = encode_json $job;
        syswrite $self->{write_fh}, "$res\n";
    }
}

sub info {
    my ($self, $job) = @_;
    my $message = "";
    if ($job->{type} eq "install") {
        $message = CPAN::DistnameInfo->new($job->{distfile})->distvname;
    } elsif ($job->{type} eq "resolve") {
        $message = $job->{package};
        if ($job->{result}{ok}) {
            $message .= " -> ". CPAN::DistnameInfo->new($job->{result}{distfile})->distvname;
        }
    }
    my $ok = $job->{result}{ok} ? "\e[32mDONE\e[m" : "\e[31mFAIL\e[m";
    warn "$$ $ok $job->{type} $message\n";
}

1;
