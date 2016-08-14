package App::cpm::Worker::Resolver::Snapshot;
use strict;
use warnings;
use App::cpm::version;
use App::cpm::Logger;
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

    my $version = $found->version_for($package);
    if (my $req_version = $job->{version}) {
        if (!App::cpm::version->parse($version)->satisfy($req_version)) {
            App::cpm::Logger->log(
                result => "WARN",
                message => "Couldn't find $job->{package} $req_version (only found $version)",
            );
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
        version  => $version,
        provides => \@provides,
    };
}

1;
