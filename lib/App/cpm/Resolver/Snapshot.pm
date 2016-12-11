package App::cpm::Resolver::Snapshot;
use strict;
use warnings;
use App::cpm::version;
use App::cpm::Logger;
use Carton::Snapshot;
our $VERSION = '0.292';

sub new {
    my ($class, %option) = @_;
    my $snapshot = Carton::Snapshot->new(path => $option{path} || "cpanfile.snapshot");
    $snapshot->load;
    my $mirror = $option{mirror} || ["http://www.cpan.org", "http://backpan.perl.org"];
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
    return unless $found;

    my $version = $found->version_for($package);
    if (my $version_range = $job->{version_range}) {
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
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
        uri => [map { "${_}authors/id/$distfile" } @{$self->{mirror}}],
        version  => $version,
        provides => \@provides,
    };
}

1;
