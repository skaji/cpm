package App::cpm::Resolver::Snapshot;
use strict;
use warnings;
use App::cpm::version;
use App::cpm::Logger;
use Carton::Snapshot;

sub new {
    my ($class, %option) = @_;
    my $snapshot = Carton::Snapshot->new(path => $option{path} || "cpanfile.snapshot");
    $snapshot->load;
    bless {
        mirror => ["http://www.cpan.org", "http://backpan.perl.org"],
        %option,
        snapshot => $snapshot
    }, $class;
}

sub snapshot { shift->{snapshot} }

sub resolve {
    my ($self, $job) = @_;
    my $package = $job->{package};
    my $found = $self->snapshot->find($package);
    return unless $found;

    my $version = $found->version_for($package);
    if (my $req_version = $job->{version}) {
        if (!App::cpm::version->parse($version)->satisfy($req_version)) {
            App::cpm::Logger->log(
                result => "WARN",
                message => "Couldn't find $job->{package} $req_version (only found $version)",
            );
            return;
        }
    }

    my @provides = map {
        my $package = $_;
        my $version = $found->provides->{$_}{version};
        $version = undef if $version eq "undef";
        +{ package => $package, version => $version };
    } sort keys %{$found->provides};

    my $distfile = $found->distfile;
    return {
        source => "cpan",
        distfile => $distfile,
        uri => [map { "$_/authors/id/$distfile" } @{$self->{mirror}}],
        version  => $version,
        provides => \@provides,
    };
}

1;
