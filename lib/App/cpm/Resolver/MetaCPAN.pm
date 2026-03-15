package App::cpm::Resolver::MetaCPAN;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::DistNotation;
use JSON::PP ();

sub new ($class, $ctx, %option) {
    my $uri = $option{uri} || "https://fastapi.metacpan.org/v1/download_url/";
    $uri =~ s{/*$}{/};
    bless { %option, uri => $uri }, $class;
}

my sub encode ($str) {
    $str =~ s/([^a-zA-Z0-9_\-.])/uc sprintf("%%%02x",ord($1))/eg;
    $str;
}

sub resolve ($self, $ctx, $task) {
    if ($self->{only_dev} and !$task->{dev}) {
        return { error => "skip, because MetaCPAN is configured to resolve dev releases only" };
    }

    my %query = (
        ( ($self->{dev} || $task->{dev}) ? (dev => 1) : () ),
        ( $task->{version_range} ? (version => $task->{version_range}) : () ),
    );
    my $query = join "&", map { "$_=" . encode($query{$_}) } sort keys %query;
    my $uri = "$self->{uri}$task->{package}" . ($query ? "?$query" : "");
    my $res;
    for (1..2) {
        $res = $ctx->{http}->get($uri);
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
