package App::cpm::Worker::Resolver;
use strict;
use warnings;
use App::cpm::Worker::Resolver::MetaDB;

sub _load_class {
    my $module = shift;
    eval "require $module; 1;" or die $@;
}

sub new {
    my ($class, %option) = @_;
    my @backends;
    push @backends, App::cpm::Worker::Resolver::MetaDB->new(%option);
    if ($option{snapshot}) {
        my $klass = "App::cpm::Worker::Resolver::Snapshot";
        _load_class $klass;
        unshift @backends, $klass->new(%option);
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
