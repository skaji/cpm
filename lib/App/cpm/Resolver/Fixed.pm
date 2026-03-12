package App::cpm::Resolver::Fixed;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Resolver::MetaDB';

sub new ($class, $ctx, @argv) {
    my %package;
    for my $argv (@argv) {
        my ($package, $fixed_version) = split /\@/, $argv;
        $package{$package} = $fixed_version;
    }
    my $self = $class->SUPER::new;
    $self->{_packages} = \%package;
    $self;
}

sub resolve ($self, $ctx, $argv) {
    my $fixed_version = $self->{_packages}{$argv->{package}};
    return { error => "not found" } if !$fixed_version;
    my $version_range = $argv->{version_range};
    if ($version_range) {
        $version_range .= ", == $fixed_version";
    } else {
        $version_range = "== $fixed_version";
    }
    $self->SUPER::resolve($ctx, { $argv->%*, version_range => $version_range });
}

1;
