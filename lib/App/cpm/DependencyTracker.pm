package App::cpm::DependencyTracker;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

# This class owns dependency state, indexes, and caches that make lookups cheap.
# App::cpm::Master owns install scheduling decisions, including phase handling,
# core/installed module checks, resolve task registration, and install failure handling.

sub new ($class) {
    bless {
        dependency_ready_by_distfile => +{},
        provider_dists_by_package => +{},
        _resolved_distribution_by_requirement => +{},
        runtime_dependency_waiting_distfiles_by_distfile => +{},
        runtime_dependency_waiting_packages_by_distfile => +{},
        runtime_dependency_waiters_by_distfile => +{},
        runtime_dependency_waiters_by_package => +{},
        runtime_dependency_dirty_by_distfile => +{},
    }, $class;
}

sub is_dependency_ready ($self, $dist) {
    my $distfile = $dist->distfile;
    $self->{dependency_ready_by_distfile}{$distfile};
}

sub mark_dependency_ready ($self, $dist) {
    my $distfile = $dist->distfile;
    my $was_ready = $self->{dependency_ready_by_distfile}{$distfile} || 0;
    $self->{dependency_ready_by_distfile}{$distfile} = 1;
    $self->_mark_dependency_ready_distfile($distfile) if !$was_ready;
}

sub add_provides ($self, $dist, $provides) {
    my $distfile = $dist->distfile;
    delete $self->{_resolved_distribution_by_requirement};
    for my $provide ($provides->@*) {
        my $package = $provide->{package};
        my $provider_dists = $self->{provider_dists_by_package}{$package} ||= [];
        push $provider_dists->@*, $dist
            if !grep { $_->distfile eq $distfile } $provider_dists->@*;
    }
}

sub resolved_distribution ($self, $package, $version_range = undef) {
    my $key = join "\0", $package, $version_range // "";
    return $self->{_resolved_distribution_by_requirement}{$key} if exists $self->{_resolved_distribution_by_requirement}{$key};

    my $provider_dists = $self->{provider_dists_by_package}{$package} || [];
    my ($resolved) = grep { $_->providing($package, $version_range) } $provider_dists->@*;
    $self->{_resolved_distribution_by_requirement}{$key} = $resolved;
    $resolved;
}

sub _mark_dependency_ready_distfile ($self, $distfile) {
    if (my $waiters = $self->{runtime_dependency_waiters_by_distfile}{$distfile}) {
        $self->{runtime_dependency_dirty_by_distfile}{$_} = 1 for keys $waiters->%*;
    }
}

sub mark_resolved_packages ($self, @packages) {
    for my $package (@packages) {
        if (my $waiters = $self->{runtime_dependency_waiters_by_package}{$package}) {
            $self->{runtime_dependency_dirty_by_distfile}{$_} = 1 for keys $waiters->%*;
        }
    }
}

sub is_runtime_dependency_dirty ($self, $dist) {
    $self->{runtime_dependency_dirty_by_distfile}{ $dist->distfile };
}

sub has_runtime_dependency_waiting ($self, $dist) {
    my $distfile = $dist->distfile;
    $self->{runtime_dependency_waiting_distfiles_by_distfile}{$distfile}
        || $self->{runtime_dependency_waiting_packages_by_distfile}{$distfile};
}

sub clear_runtime_dependency_waiting ($self, $dist) {
    my $distfile = $dist->distfile;
    my $waiting_distfiles = $self->{runtime_dependency_waiting_distfiles_by_distfile}{$distfile} || {};
    for my $waiting_distfile (keys $waiting_distfiles->%*) {
        delete $self->{runtime_dependency_waiters_by_distfile}{$waiting_distfile}{$distfile};
        delete $self->{runtime_dependency_waiters_by_distfile}{$waiting_distfile}
            if !keys $self->{runtime_dependency_waiters_by_distfile}{$waiting_distfile}->%*;
    }
    my $waiting_packages = $self->{runtime_dependency_waiting_packages_by_distfile}{$distfile} || {};
    for my $package (keys $waiting_packages->%*) {
        delete $self->{runtime_dependency_waiters_by_package}{$package}{$distfile};
        delete $self->{runtime_dependency_waiters_by_package}{$package}
            if !keys $self->{runtime_dependency_waiters_by_package}{$package}->%*;
    }
    delete $self->{runtime_dependency_waiting_distfiles_by_distfile}{$distfile};
    delete $self->{runtime_dependency_waiting_packages_by_distfile}{$distfile};
    delete $self->{runtime_dependency_dirty_by_distfile}{$distfile};
}

sub remember_runtime_dependency_waiting ($self, $dist, $waiting_distfiles, $waiting_packages) {
    my $distfile = $dist->distfile;
    $self->clear_runtime_dependency_waiting($dist);

    if ($waiting_distfiles->%* || $waiting_packages->%*) {
        $self->{runtime_dependency_waiting_distfiles_by_distfile}{$distfile} = $waiting_distfiles;
        $self->{runtime_dependency_waiting_packages_by_distfile}{$distfile} = $waiting_packages;
        $self->{runtime_dependency_waiters_by_distfile}{$_}{$distfile} = 1 for keys $waiting_distfiles->%*;
        $self->{runtime_dependency_waiters_by_package}{$_}{$distfile} = 1 for keys $waiting_packages->%*;
    }
}

1;
