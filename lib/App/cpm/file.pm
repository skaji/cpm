package App::cpm::file;
use strict;
use warnings;

use CPAN::Meta::Prereqs;
use YAML::PP ();

sub new {
    my ($class, $file) = @_;
    my ($data) = YAML::PP->new->load_file($file);
    bless { data => $data }, $class;
}

sub cpanmeta_prereqs {
    my $self = shift;
    my %hash;
    for my $phase (sort keys %{$self->{data}{prereqs}}) {
        for my $type (sort keys %{$self->{data}{prereqs}{$phase}}) {
            my $specs = $self->{data}{prereqs}{$phase}{$type};
            for my $package (sort keys %$specs) {
                my $option = $specs->{$package} || +{};
                my $version = $option->{version} || 0;
                $hash{$phase}{$type}{$package} = $version;
            }
        }
    }
    CPAN::Meta::Prereqs->new(\%hash);
}

1;
