package App::cpm::Resolver::Snapshot;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::Git;
use App::cpm::Resolver::Git;
use App::cpm::version;
use Carton::Snapshot;

sub new {
    my ($class, %option) = @_;
    my $snapshot = Carton::Snapshot->new(path => $option{path} || "cpanfile.snapshot");
    $snapshot->load;
    my $mirror = $option{mirror} || ["https://cpan.metacpan.org/"];
    s{/*$}{/} for @$mirror;
    bless {
        %option,
        mirror => $mirror,
        snapshot => $snapshot
    }, $class;
}

sub snapshot { shift->{snapshot} }

sub resolve {
    my ($self, $job) = @_;
    my $package = $job->{package};
    my $found = $self->snapshot->find($package);
    if (!$found) {
        return { error => "not found, @{[$self->snapshot->path]}" };
    }

    my $version = $found->version_for($package);
    if (my $version_range = $job->{version_range}) {
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->snapshot->path]}" };
        }
    }

    my @provides = map {
        my $package = $_;
        my $version = $found->provides->{$_}{version};
        +{ package => $package, version => $version };
    } sort keys %{$found->provides};

    if (App::cpm::Git->is_git_uri($found->pathname)) {
        my $uri = $found->pathname;
        $uri =~ s/@(\p{IsXDigit}{40})$//;
        my $rev = $1;
        if (my ($want_rev) = App::cpm::Resolver::Git->fetch_rev($job->{uri}, $job->{ref})) {
            return unless index($rev, $want_rev) == 0;
        }
        return {
            source => "git",
            uri => $uri,
            ref => $job->{ref},
            rev => $1,
            version  => $version || 0,
            provides => \@provides,
        };
    } elsif ($job->{source} && $job->{source} eq 'git') {
        return;
    }

    my $dist = App::cpm::DistNotation->new_from_dist($found->distfile);
    return {
        source => "cpan",
        distfile => $dist->distfile,
        uri => [map { $dist->cpan_uri($_) } @{$self->{mirror}}],
        version  => $version || 0,
        provides => \@provides,
    };
}

1;
