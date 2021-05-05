package App::cpm::Resolver::MetaCPAN;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::HTTP;
use JSON::PP ();

sub new {
    my ($class, %option) = @_;
    my $uri = $option{uri} || "https://fastapi.metacpan.org/v1/download_url/";
    $uri =~ s{/*$}{/};
    my $http = App::cpm::HTTP->create;
    bless { %option, uri => $uri, http => $http }, $class;
}

sub _encode {
    my $str = shift;
    $str =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    $str;
}

sub resolve {
    my ($self, $task) = @_;
    if ($self->{only_dev} and !$task->{dev}) {
        return { error => "skip, because MetaCPAN is configured to resolve dev releases only" };
    }

    my %query = (
        ( ($self->{dev} || $task->{dev}) ? (dev => 1) : () ),
        ( $task->{version_range} ? (version => $task->{version_range}) : () ),
    );
    my $query = join "&", map { "$_=" . _encode($query{$_}) } sort keys %query;
    my $uri = "$self->{uri}$task->{package}" . ($query ? "?$query" : "");
    my $res;
    for (1..2) {
        $res = $self->{http}->get($uri);
        last if $res->{success} or $res->{status} == 404;
    }
    if (!$res->{success}) {
        my $error = "$res->{status} $res->{reason}, $uri";
        $error .= ", $res->{content}" if $res->{status} == 599;
        return { error => $error };
    }

    my $hash = eval { JSON::PP::decode_json($res->{content}) } or return;
    my $dist = App::cpm::DistNotation->new_from_uri($hash->{download_url});
    return {
        source => "cpan", # XXX
        distfile => $dist->distfile,
        package => $task->{package},
        version => $hash->{version} || 0,
        uri => $hash->{download_url},
    };
}

1;
