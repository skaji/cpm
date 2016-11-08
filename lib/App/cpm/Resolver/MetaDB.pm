package App::cpm::Resolver::MetaDB;
use strict;
use warnings;
use utf8;
our $VERSION = '0.214';

use HTTP::Tiny;
use CPAN::Meta::YAML;
use App::cpm::version;
use App::cpm::Logger;

sub new {
    my ($class, %option) = @_;
    my $uri = $option{uri} || "http://cpanmetadb.plackperl.org/v1.0/";
    my $mirror = $option{mirror} || ["http://www.cpan.org/", "http://backpan.perl.org/"];
    s{/*$}{/} for $uri, @$mirror;
    my $http = HTTP::Tiny->new(timeout => 15, keep_alive => 1, agent => "App::cpm/$VERSION");
    bless {
        %option,
        http => $http,
        uri => $uri,
        mirror => $mirror,
    }, $class;
}

sub resolve {
    my ($self, $job) = @_;

    if (defined $job->{version} and $job->{version} =~ /(?:<|!=|==)/) {
        my $res = $self->{http}->get( "$self->{uri}history/$job->{package}" );
        return unless $res->{success};

        my @found;
        for my $line ( split /\r?\n/, $res->{content} ) {
            if ($line =~ /^$job->{package}\s+(\S+)\s+(\S+)$/) {
                push @found, {
                    version => $1,
                    version_o => App::cpm::version->parse($1),
                    distfile => $2,
                };
            }
        }

        return unless @found;
        $found[-1]->{latest} = 1;

        my $match;
        for my $try (sort { $b->{version_o} <=> $a->{version_o} } @found) {
            if ($try->{version_o}->satisfy($job->{version})) {
                $match = $try, last;
            }
        }

        if ($match) {
            my $distfile = $match->{distfile};
            return {
                source => "cpan",
                package => $job->{package},
                version => $match->{version},
                uri     => [map { "${_}authors/id/$distfile" } @{$self->{mirror}}],
                distfile => $distfile,
            };
        }
    } else {
        my $res = $self->{http}->get( "$self->{uri}package/$job->{package}" );
        return unless $res->{success};

        my $yaml = CPAN::Meta::YAML->read_string($res->{content});
        my $meta = $yaml->[0];
        if (!App::cpm::version->parse($meta->{version})->satisfy($job->{version})) {
            return;
        }
        my @provides = map {
            my $package = $_;
            my $version = $meta->{provides}{$_};
            $version = undef if $version eq "undef";
            +{ package => $package, version => $version };
        } sort keys %{$meta->{provides}};

        my $distfile = $meta->{distfile};
        return {
            source => "cpan",
            distfile => $distfile,
            uri => [map { "${_}authors/id/$distfile" } @{$self->{mirror}}],
            version  => $meta->{version},
            provides => \@provides,
        };
    }
    return;
}

1;
