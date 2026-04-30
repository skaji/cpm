package App::cpm::DependencyIndex;
use v5.24;
use warnings;
use experimental qw(signatures);

sub new ($class) {
    bless {
        provided_by_package => +{},
        runtime_waiting_by_distfile => +{},
        runtime_waiting_by_package => +{},
        runtime_dirty => +{},
    }, $class;
}

sub index_provides ($self, $distribution, $provides) {
    my $distfile = $distribution->distfile;
    for my $provide ($provides->@*) {
        my $package = $provide->{package};
        my $candidates = $self->{provided_by_package}{$package} ||= [];
        push $candidates->@*, $distribution
            if !grep { $_->distfile eq $distfile } $candidates->@*;
    }
}

sub providers_for ($self, $package) {
    ($self->{provided_by_package}{$package} || [])->@*;
}

sub mark_distfile_ready ($self, $distfile) {
    if (my $waiters = $self->{runtime_waiting_by_distfile}{$distfile}) {
        $self->{runtime_dirty}{$_} = 1 for keys $waiters->%*;
    }
}

sub mark_packages_resolved ($self, @package) {
    for my $package (@package) {
        if (my $waiters = $self->{runtime_waiting_by_package}{$package}) {
            $self->{runtime_dirty}{$_} = 1 for keys $waiters->%*;
        }
    }
}

sub is_runtime_dirty ($self, $dist) {
    $self->{runtime_dirty}{ $dist->distfile };
}

sub has_runtime_waiting ($self, $dist) {
    $dist->{_runtime_waiting_distfiles} || $dist->{_runtime_waiting_packages};
}

sub clear_runtime_waiting ($self, $dist) {
    my $distfile = $dist->distfile;
    my $waiting_distfiles = $dist->{_runtime_waiting_distfiles} || {};
    for my $wait_distfile (keys $waiting_distfiles->%*) {
        delete $self->{runtime_waiting_by_distfile}{$wait_distfile}{$distfile};
        delete $self->{runtime_waiting_by_distfile}{$wait_distfile}
            if !keys $self->{runtime_waiting_by_distfile}{$wait_distfile}->%*;
    }
    my $waiting_packages = $dist->{_runtime_waiting_packages} || {};
    for my $package (keys $waiting_packages->%*) {
        delete $self->{runtime_waiting_by_package}{$package}{$distfile};
        delete $self->{runtime_waiting_by_package}{$package}
            if !keys $self->{runtime_waiting_by_package}{$package}->%*;
    }
    delete $dist->{_runtime_waiting_distfiles};
    delete $dist->{_runtime_waiting_packages};
    delete $self->{runtime_dirty}{$distfile};
}

sub remember_runtime_waiting ($self, $dist, $wait_distfile, $wait_package) {
    my $distfile = $dist->distfile;
    $self->clear_runtime_waiting($dist);

    if ($wait_distfile->%* || $wait_package->%*) {
        $dist->{_runtime_waiting_distfiles} = $wait_distfile;
        $dist->{_runtime_waiting_packages} = $wait_package;
        $self->{runtime_waiting_by_distfile}{$_}{$distfile} = 1 for keys $wait_distfile->%*;
        $self->{runtime_waiting_by_package}{$_}{$distfile} = 1 for keys $wait_package->%*;
    }
}

1;
