package PrereqsFromCPMfile;
use strict;
use warnings;

use Moose;
use App::cpm::file;
with 'Dist::Zilla::Role::PrereqSource';

sub register_prereqs {
    my $self = shift;
    my $cpmfile = App::cpm::file->new("cpm.yml");
    my $prereqs = $cpmfile->cpanmeta_prereqs->as_string_hash;
    for my $phase (keys %$prereqs) {
        for my $type (keys %{$prereqs->{$phase}}) {
            $self->zilla->register_prereqs(
                { type => $type, phase => $phase },
                %{$prereqs->{$phase}{$type}},
            );
        }
    }
}

__PACKAGE__->meta->make_immutable;

1;
