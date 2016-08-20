package App::cpm::Worker::Resolver;
use strict;
use warnings;

sub _load_class {
    my $module = shift;
    eval "require $module; 1;" or die $@;
}

sub new {
    my ($class, %option) = @_;

    my @backends;
    for my $r (@{$option{resolver}}) {
        my $klass;
        if ($r->{cpanmetadb}) {
            $klass = "App::cpm::Worker::Resolver::MetaDB";
        } elsif ($r->{snapshot}) {
            $klass = "App::cpm::Worker::Resolver::Snapshot";
        } else {
            die "Unknown option";
        }
        _load_class $klass;
        push @backends, $klass->new(%$r);
    }
    bless { backends => \@backends }, $class;
}

sub work {
    my ($self, $job) = @_;
    my $res;
    for my $backend (@{$self->{backends}}) {
        $res = $backend->work($job);
        return $res if $res->{ok};
    }
    $res;
}

1;
