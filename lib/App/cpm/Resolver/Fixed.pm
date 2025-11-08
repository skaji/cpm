package App::cpm::Resolver::Fixed;
use strict;
use warnings;

use parent 'App::cpm::Resolver::MetaDB';

sub new {
    my $class = shift;
    my $ctx = shift;
    my %package;
    for my $argv (@_) {
        my ($package, $fixed_version) = split /\@/, $argv;
        $package{$package} = $fixed_version;
    }
    my $self = $class->SUPER::new;
    $self->{_packages} = \%package;
    $self;
}

sub resolve {
    my ($self, $ctx, $argv) = @_;
    my $fixed_version = $self->{_packages}{$argv->{package}};
    return { error => "not found" } if !$fixed_version;
    my $version_range = $argv->{version_range};
    if ($version_range) {
        $version_range .= ", == $fixed_version";
    } else {
        $version_range = "== $fixed_version";
    }
    $self->SUPER::resolve($ctx, { %$argv, version_range => $version_range });
}

1;
