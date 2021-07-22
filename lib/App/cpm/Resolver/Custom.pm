package App::cpm::Resolver::Custom;
use strict;
use warnings;

use App::cpm::DistNotation;

sub new {
    my ($class, %argv) = @_;

    my $from = $argv{from};
    my $requirements = $argv{requirements};
    my $mirror = $argv{mirror} || 'https://cpan.metacpan.org/';
    $mirror =~ s{/*$}{/};

    my $self = bless {
        from => $from,
        mirror => $mirror,
        requirements => $requirements,
    }, $class;
    $self->_load;
    $self;
}

sub _load {
    my $self = shift;

    my %resolve;
    for my $package (sort keys %{$self->{requirements}}) {
        my $options = $self->{requirements}{$package};

        my $uri;
        if ($uri = $options->{git}) {
            $resolve{$package} = {
                source => 'git',
                uri => $uri,
                ref => $options->{ref},
                provides => [{package => $package}],
            };
        } elsif ($uri = $options->{dist}) {
            my $dist = App::cpm::DistNotation->new_from_dist($uri);
            die "Unsupported dist '$uri' found in $self->{from}\n" if !$dist;
            my $cpan_uri = $dist->cpan_uri($options->{mirror} || $self->{mirror});
            $resolve{$package} = {
                source => 'cpan',
                uri => $cpan_uri,
                distfile => $dist->distfile,
                provides => [{package => $package}],
            };
        } elsif ($uri = $options->{url}) {
            die "Unsupported url '$uri' found in $self->{from}\n" if $uri !~ m{^(?:https?|file)://};
            my $dist = App::cpm::DistNotation->new_from_uri($uri);
            my $source = $dist ? 'cpan' : $uri =~ m{^file://} ? 'local' : 'http';
            $resolve{$package} = {
                source => $source,
                uri => $dist ? $dist->cpan_uri : $uri,
                ($dist ? (distfile => $dist->distfile) : ()),
                provides => [{package => $package}],
            };
        }
    }
    $self->{resolve} = \%resolve;
}

sub effective {
    my $self = shift;
    %{$self->{resolve}} ? 1 : 0;
}

sub resolve {
    my ($self, $task) = @_;
    my $found = $self->{resolve}{$task->{package}};
    if (!$found) {
        return { error => "not found in $self->{from}" };
    }
    $found; # TODO handle version
}

1;
