package App::cpm::Resolver::MetaCPAN;
use strict;
use warnings;
use JSON::PP ();
our $VERSION = '0.293';

my $HTTP_CLIENT_CLASS = do {
    if (eval { require IO::Socket::SSL }) {
        require HTTP::Tiny;
        "HTTP::Tiny";
    } else {
        require HTTP::Tinyish;
        "HTTP::Tinyish";
    }
};

sub new {
    my ($class, %option) = @_;
    my $uri = $option{uri} || "https://fastapi.metacpan.org/v1/download_url/";
    $uri =~ s{/*$}{/};
    my $http = $HTTP_CLIENT_CLASS->new(timeout => 10, agent => "App::cpm/$VERSION");
    bless { %option, uri => $uri, http => $http }, $class;
}

sub _encode {
    my $str = shift;
    $str =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    $str;
}

sub resolve {
    my ($self, $job) = @_;
    if ($self->{only_dev} and !$job->{dev}) {
        return;
    }

    my %query = (
        ( ($self->{dev} || $job->{dev}) ? (dev => 1) : () ),
        ( $job->{version_range} ? (version => $job->{version_range}) : () ),
    );
    my $query = join "&", map { "$_=" . _encode($query{$_}) } sort keys %query;
    my $uri = "$self->{uri}$job->{package}" . ($query ? "?$query" : "");
    my $res;
    for (1..2) {
        $res = $self->{http}->get($uri);
        last if $res->{success} or !($res->{status} == 599 and $res->{content} =~ /timed out/);
    }
    return unless $res->{success};

    my $hash = eval { JSON::PP::decode_json($res->{content}) } or return;
    my ($distfile) = $hash->{download_url} =~ m{/authors/id/(.+)};
    return {
        source => "cpan", # XXX
        distfile => $distfile,
        package => $job->{package},
        version => $hash->{version},
        uri => $hash->{download_url},
    };
}

1;
