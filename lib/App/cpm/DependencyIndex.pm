package App::cpm::DependencyIndex;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

sub new ($class) {
    bless {
        dependency_ready => +{},
        provided_by_package => +{},
        _resolved_distribution => +{},
        runtime_waiting_by_distfile => +{},
        runtime_waiting_by_package => +{},
        runtime_dirty => +{},
    }, $class;
}

sub dependency_ready ($self, $dist, @argv) {
    my $distfile = $dist->distfile;
    if (@argv) {
        my $ready = $argv[0] ? 1 : 0;
        my $was_ready = $self->{dependency_ready}{$distfile} || 0;
        $self->{dependency_ready}{$distfile} = $ready;
        $self->mark_distfile_ready($distfile) if !$was_ready && $ready;
    }
    $self->{dependency_ready}{$distfile};
}

sub index_provides ($self, $dist, $provides) {
    my $distfile = $dist->distfile;
    delete $self->{_resolved_distribution};
    for my $provide ($provides->@*) {
        my $package = $provide->{package};
        my $candidates = $self->{provided_by_package}{$package} ||= [];
        push $candidates->@*, $dist
            if !grep { $_->distfile eq $distfile } $candidates->@*;
    }
}

sub resolved_distribution ($self, $package, $version_range = undef) {
    my $key = join "\0", $package, $version_range // "";
    return $self->{_resolved_distribution}{$key} if exists $self->{_resolved_distribution}{$key};

    my $candidates = $self->{provided_by_package}{$package} || [];
    my ($resolved) = grep { $_->providing($package, $version_range) } $candidates->@*;
    $self->{_resolved_distribution}{$key} = $resolved;
    $resolved;
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
