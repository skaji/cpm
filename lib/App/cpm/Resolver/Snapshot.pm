package App::cpm::Resolver::Snapshot;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::DistNotation;
use App::cpm::version;
use Carton::Snapshot;

sub new ($class, $ctx, %argv) {
    my $snapshot = Carton::Snapshot->new(path => $argv{path} || "cpanfile.snapshot");
    $snapshot->load;
    my $mirror = $argv{mirror} || "https://cpan.metacpan.org/";
    $mirror =~ s{/*$}{/};
    bless {
        %argv,
        mirror => $mirror,
        snapshot => $snapshot
    }, $class;
}

sub snapshot ($self) { $self->{snapshot} }

sub resolve ($self, $ctx, $task) {
    my $package = $task->{package};
    my $found = $self->snapshot->find($package);
    if (!$found) {
        return { error => "not found, @{[$self->snapshot->path]}" };
    }

    my $version = $found->version_for($package);
    if (my $version_range = $task->{version_range}) {
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->snapshot->path]}" };
        }
    }

    my @provides = map {
        my $package = $_;
        my $version = $found->provides->{$_}{version};
        +{ package => $package, version => $version };
    } sort keys $found->provides->%*;

    my $dist = App::cpm::DistNotation->new_from_dist($found->distfile);
    return {
        source => "cpan",
        distfile => $dist->distfile,
        uri => $dist->cpan_uri($self->{mirror}),
        version  => $version || 0,
        provides => \@provides,
    };
}

1;
