package App::cpm::Resolver::Git;
use strict;
use warnings;
use App::cpm::Git;
use App::cpm::version;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub fetch_rev {
    my ($class, $uri, $ref) = @_;
    return unless $ref;

    ($uri) = App::cpm::Git->split_uri($uri);
    my ($rev, $version) = `git ls-remote --refs $uri $ref` =~ /^(\p{IsXDigit}{40})\s+(?:refs\/tags\/(v?\d+\.\d+(?:\.\d+)?)$)?/;
    $rev = $ref if !$rev && $ref =~ /^[0-9a-fA-F]{4,}$/;
    return ($rev, $version);
}

sub resolve {
    my ($self, $job) = @_;
    return unless $job->{source} && $job->{source} eq 'git';

    my ($rev, $version);
    if ($job->{ref}) {
        ($rev, $version) = $self->fetch_rev($job->{uri}, $job->{ref});
    } else {
        my @tags;
        my ($uri) = App::cpm::Git->split_uri($job->{uri});
        my $out = `git ls-remote --tags --refs $uri "*.*"`;
        while ($out =~ /^(\p{IsXDigit}{40})\s+refs\/tags\/(.+)$/mg) {
            my ($r, $v) = ($1, $2);
            push @tags, {
                version => App::cpm::version->parse($v),
                rev     => $r,
            };
        }
        if (@tags) {
            foreach my $tag (sort { $b->{version} <=> $a->{version} } @tags) {
                if ($tag->{version}->satisfy($job->{version_range})) {
                    $version = $tag->{version}->stringify;
                    $rev = $tag->{rev};
                    last;
                }
            }
        } else {
            ($rev) = `git ls-remote $uri HEAD` =~ /^(\p{IsXDigit}+)\s/;
        }
    }
    return { error => 'repo or ref not found' } unless $rev;

    return {
        source => 'git',
        uri => $job->{uri},
        ref => $job->{ref},
        rev => $rev,
        package => $job->{package},
        version => $version,
    };
}

1;
