package Acme::CPAN::Installer::Worker::Resolver;
use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use IO::Socket::SSL;
use CPAN::Meta::YAML;
use JSON::PP;

sub new {
    my ($class, %option) = @_;
    $option{distfile_url} ||= "https://cpanmetadb-provides.herokuapp.com/v1.1/package";
    my $ua = HTTP::Tiny->new(timeout => 5);
    bless { %option, ua => $ua }, $class;
}

sub work {
    my ($self, $job) = @_;
    my ($distfile, $provides, $requirements)
        = $self->resolve($job->{package}, $job->{version});
    return { ok => 0 } unless $distfile;
    +{ ok => 1, distfile => $distfile, provides => $provides, requirements => $requirements };
}

sub resolve {
    my ($self, $package, $version) = @_;
    my $res = $self->{ua}->get( $self->{distfile_url} . "/$package" );
    if ($res->{success} and my $yaml = CPAN::Meta::YAML->read_string($res->{content})) {
        my $meta = $yaml->[0] or return;
        return ($meta->{distfile}, $meta->{provides}, $meta->{requirements});
    }
    return;
}

1;
