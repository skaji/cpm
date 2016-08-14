package App::cpm::Worker::Resolver::Snapshot;
use strict;
use warnings;
use CPAN::Meta::Requirements;
use Carton::Snapshot;

sub new {
    my ($class, %option) = @_;
    my $snapshot = Carton::Snapshot->new(path => $option{snapshot} || "cpanfile.snapshot");
    $snapshot->load;
    bless { snapshot => $snapshot }, $class;
}

sub snapshot { shift->{snapshot} }

sub work {
    my ($self, $job) = @_;
    my $package = $job->{package};
    my $found = $self->snapshot->find($package);
    return { ok => 0 } unless $found;

    my $snapshot_version = $found->version_for($package);
    if (my $version = $job->{version}) {
        my $reqs = CPAN::Meta::Requirements->from_string_hash({ $package => $version });
        if (!$reqs->accepts_module($package, $snapshot_version)) {
            return { ok => 0 };
        }
    }

    my @provides = map {
        my $package = $_;
        my $version = $found->provides->{$_}{version};
        $version = undef if $version eq "undef";
        +{ package => $package, version => $version };
    } sort keys %{$found->provides};

    return {
        ok => 1,
        distfile => $found->distfile,
        version  => $snapshot_version,
        provides => \@provides,
    };
}

1;
