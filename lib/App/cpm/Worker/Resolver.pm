package App::cpm::Worker::Resolver;
use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use CPAN::Meta::YAML;
use version;

sub new {
    my ($class, %option) = @_;
    my $ua = HTTP::Tiny->new(timeout => 5);
    bless { %option, ua => $ua }, $class;
}

sub work {
    my ($self, $job) = @_;
    my $res = $self->{ua}->get($self->{cpanmetadb} . "/v1.1/package/$job->{package}");
    if ($res->{success}) {
        my $yaml = CPAN::Meta::YAML->read_string($res->{content});
        my $meta = $yaml->[0];
        my $version = $meta->{version} eq "undef" ? 0 : $meta->{version};
        if (my $req_version = $job->{version}) {
            unless (version->parse($req_version) <= version->parse($version)) {
                warn "-> Couldn't find $job->{package} $req_version (only found $version)\n";
                return { ok => 0 };
            }
        }
        return {
            ok => 1,
            distfile => $meta->{distfile},
            version => $meta->{version},
            provides => $meta->{provides} || [],
        };
    }
    return { ok => 0 };
}

1;
