package App::cpm2::Resolver;
use strict;
use warnings;

use HTTP::Tiny;
use YAML::PP ();

my $YAML = YAML::PP->new;

sub new {
    my $class = shift;
    my $http = HTTP::Tiny->new(timeout => 5);
    my $url = 'https://cpanmetadb.plackperl.org/v1.0';
    my $mirror = 'https://cpan.metacpan.org';
    bless { http => $http, url => $url, mirror => $mirror }, $class;
}

sub resolve {
    my ($self, $package, $version_range) = @_;

    my $url = sprintf "%s/package/%s", $self->{url}, $package;
    my $res = $self->{http}->get($url);

    if (!$res->{success}) {
        return (undef, "$url, $res->{status} $res->{reason}");
    }

    my ($payload) = $YAML->load_string($res->{content});

    return {
        disturl  => (sprintf "%s/authors/id/%s", $self->{mirror}, $payload->{distfile}),
        provides => $payload->{provides},
        version  => $payload->{version},
    };
}

1;
