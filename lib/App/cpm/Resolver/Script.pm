package App::cpm::Resolver::Script;
use strict;
use warnings;
our $VERSION = '0.211';

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
    my $uri = $option{uri} || "https://metacpan.org/pod/";
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
    return if $job->{package} =~ /::/;
    my $uri = "$self->{uri}$job->{package}";
    my $res;
    for (1..2) {
        print "D:uri=$uri\n";
        $res = $self->{http}->get($uri);
        last if $res->{success} or !($res->{status} == 599 and $res->{content} =~ /timed out/);
    }
    return unless $res->{success};

    my ($distfile) = $res->{content} =~ m{/authors/id/([^"]+)} or return;
    my ($version) = $res->{content} =~ m{<option selected.+?>\s+(\S+)}s;
    my $download_url = "$self->{mirror}authors/id/$distfile";

    return {
        source => "cpan", # XXX
        distfile => $distfile,
        package => $job->{package},
        version => $version,
        uri => $download_url,
    };
}

1;
