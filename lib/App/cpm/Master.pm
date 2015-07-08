package App::cpm::Master;
use strict;
use warnings;
use utf8;
use App::cpm::Distribution;
use App::cpm::Job;
use IO::Handle;
use IO::Select;
use Module::CoreList;
use Module::Metadata;
use version;

sub new {
    my ($class, %option) = @_;
    bless {
        %option,
        master => 1,
        workers => +{},
        jobs => +{},
        distributions => +{},
        _fail_resolve => +{},
        _fail_install => +{},
    }, $class;
}

sub fail {
    my $self = shift;
    my @fail_resolve = sort keys %{$self->{_fail_resolve}};
    my @fail_install = sort keys %{$self->{_fail_install}};
    return if !@fail_resolve && !@fail_install;
    { resolve => \@fail_resolve, install => \@fail_install };
}

sub is_master { shift->{master} }

{
    package
        App::cpm::_Worker;
    use JSON::PP;
    sub new {
        my ($class, %option) = @_;
        bless { _written => 0, %option}, $class;
    }
    sub has_result { shift->{_written} }
    sub read_fh  { shift->{read_fh}  }
    sub write_fh { shift->{write_fh} }
    sub pid { shift->{pid} }
    sub write {
        my ($self, $job) = @_;
        if ($self->{_written} != 0) { die }
        $self->{_written}++;
        $job->in_charge($self->pid);
        my %copy = %$job;
        my $encoded = encode_json \%copy;
        syswrite $self->write_fh, "$encoded\n";
    }
    sub work { shift->write(@_) } # alias
    sub read {
        my $self = shift;
        if ($self->{_written} != 1) { die }
        $self->{_written}--;
        my $read_fh = $self->read_fh;
        my $string = <$read_fh>;
        decode_json $string;
    }
    sub result { shift->read } # alias
}

sub handles {
    my $self = shift;
    map { ($_->read_fh, $_->write_fh) } $self->workers;
}

sub worker {
    my ($self, $worker_pid) = @_;
    $self->{workers}{$worker_pid};
}

sub workers {
    my $self = shift;
    values %{$self->{workers}};
}

sub spawn_worker {
    my ($self, $cb) = @_;
    $self->is_master or die;
    pipe my $read_fh1, my $write_fh1;
    pipe my $read_fh2, my $write_fh2;
    my $pid = fork // die;
    if ($pid == 0) {
        $self->{master} = 0;
        close $_ for $read_fh1, $write_fh2, $self->handles;
        $write_fh1->autoflush(1);
        $cb->($read_fh2, $write_fh1);
        exit;
    }
    close $_ for $write_fh1, $read_fh2;
    $write_fh2->autoflush(1);
    $self->{workers}{$pid} = App::cpm::_Worker->new(
        pid => $pid, read_fh => $read_fh1, write_fh => $write_fh2,
    );
}

sub _can_read {
    my ($self, @workers) = @_;
    $self->is_master or die;
    @workers = $self->workers unless @workers;
    my $select = IO::Select->new( map { $_->read_fh } @workers );
    my @ready = $select->can_read; # blocking

    my @return;
    for my $worker (@workers) {
        if (grep { $worker->read_fh == $_ } @ready) {
            push @return, $worker;
        }
    }
    return @return;
}

sub shutdown_workers {
    my $self = shift;
    close $_ for map { ($_->write_fh, $_->read_fh) } $self->workers;
    while (%{$self->{workers}}) {
        my $pid = wait;
        if ($pid == -1) {
            warn "wait() returns -1\n";
        } elsif (my $worker = delete $self->{workers}{$pid}) {
            close $worker->read_fh;
        } else {
            warn "wait() unexpectedly returns $pid\n";
        }
    }
}

sub ready_workers {
    my ($self, @workers) = @_;
    $self->is_master or die;
    @workers = $self->workers unless @workers;
    my @ready = grep { $_->{_written} == 0 } @workers;
    return @ready if @ready;
    $self->_can_read(@workers);
}


## job related method

sub jobs { values %{shift->{jobs}} }

sub add_job {
    my ($self, %job) = @_;
    my $new = App::cpm::Job->new(%job);
    if (grep { $_->equals($new) } $self->jobs) {
        # warn "already registered job: " . $new->uid . "\n";
        return 0;
    } else {
        $self->{jobs}{$new->uid} = $new;
        return 1;
    }
}

sub get_job {
    my $self = shift;
    if (my ($job) = grep { !$_->in_charge } $self->jobs) {
        return $job;
    }
    $self->_calculate_jobs;
    return unless $self->jobs;
    if (my ($job) = grep { !$_->in_charge } $self->jobs) {
        return $job;
    }

    my @running_workers = map { $self->worker($_->in_charge) } $self->jobs;
    my @done_workers = $self->ready_workers(@running_workers);
    $self->register_result($_->result) for @done_workers;
    $self->get_job;
}

sub register_result {
    my ($self, $result) = @_;
    my ($job) = grep { $_->uid eq $result->{uid} } $self->jobs;
    die "Missing job that has uid=$result->{uid}" unless $job;

    %{$job} = %{$result}; # XXX

    my $method = "_register_@{[$job->{type}]}_result";
    $self->$method($job);
    $self->remove_job($job);
    return 1;
}

sub remove_job {
    my ($self, $job) = @_;
    delete $self->{jobs}{$job->uid};
}

sub distributions { values %{shift->{distributions}} }

sub distribution {
    my ($self, $distfile) = @_;
    $self->{distributions}{$distfile};
}

sub _calculate_jobs {
    my $self = shift;

    my @distributions
        = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;

    if (my @dists = grep { $_->resolved } @distributions) {
        for my $dist (@dists) {
            $self->add_job(type => "fetch", distfile => $dist->distfile);
        }
    }

    if (my @dists = grep { $_->fetched } @distributions) {
        for my $dist (@dists) {
            my ($is_satisfied, @need_resolve)
                = $self->_is_satisfied($dist->configure_requirements);
            if ($is_satisfied) {
                $self->add_job(
                    type => "configure",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->distfile,
                );
            } elsif (@need_resolve) {
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            }
        }
    }

    if (my @dists = grep { $_->configured } @distributions) {
        for my $dist (@dists) {
            my ($is_satisfied, @need_resolve)
                = $self->_is_satisfied($dist->requirements);
            if ($is_satisfied) {
                $self->add_job(
                    type => "install",
                    meta => $dist->meta,
                    distdata => $dist->distdata,
                    directory => $dist->directory,
                    distfile => $dist->distfile,
                );
            } elsif (@need_resolve) {
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            }
        }
    }
}

sub _register_resolve_job {
    my ($self, @package) = @_;
    my $ok = 1;
    for my $package (@package) {
        if ($self->{_fail_resolve}{$package->{package}}) {
            $ok = 0;
            next;
        }
        $self->add_job(
            type => "resolve",
            package => $package->{package},
            version => $package->{version},
        );
    }
    return $ok;
}

sub is_installed {
    my ($self, $package, $version) = @_;
    my $info = Module::Metadata->new_from_module($package, inc => $self->{inc});
    return unless $info;
    return 1 unless $version;
    version->parse($version) <= version->parse($info->version);
}

sub is_core {
    my ($class, $package, $version) = @_;
    return 1 if $package eq "perl";
    if (exists $Module::CoreList::version{$]}{$package}) {
        return 1 unless $version;
        my $core_version = $Module::CoreList::version{$]}{$package};
        return unless $core_version;
        return version->parse($version) <= version->parse($core_version);
    }
    return;
}

sub _is_satisfied {
    my ($self, $requirements) = @_;
    my $is_satisfied = 1;
    my @need_resolve;
    my @distributions = $self->distributions;
    for my $req (@$requirements) {
        my ($package, $version) = @{$req}{qw(package version)};
        next if $self->is_core($package, $version);
        next if $self->is_installed($package, $version);
        my ($resolved) = grep { $_->providing($package, $version) } @distributions;
        next if $resolved && $resolved->installed;

        $is_satisfied = 0;
        if (!$resolved) {
            push @need_resolve, { package => $package, version => $version };
        }
    }
    return ($is_satisfied, @need_resolve);
}

sub add_distribution {
    my ($self, $distribution) = @_;
    my $distfile = $distribution->distfile;
    if (exists $self->{distributions}{$distfile}) {
        # warn "already registerd dist: $distfile\n";
        return 0;
    } else {
        $self->{distributions}{$distfile} = $distribution;
        return 1;
    }
}

sub _register_resolve_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_resolve}{$job->{package}}++;
        return;
    }
    if ($job->{distfile} =~ m{/perl-5[^/]+$}) {
        warn "$$ \e[31mFAIL\e[m \e[36minstall\e[m   Cannot upgrade core module $job->{package}.\n";
        $self->{_fail_install}{$job->{package}}++; # XXX
        return;
    }

    if ($self->is_installed($job->{package}, $job->{version})) {
        my $version = $job->{version} || 0;
        warn "$$ \e[32mDONE\e[m \e[36minstall\e[m   $job->{package} is up to date. ($version)\n";
        return;
    }

    my $distribution = App::cpm::Distribution->new(
        distfile => $job->{distfile},
        provides => $job->{provides},
    );
    my $added = $self->add_distribution($distribution);
    unless ($added) {
        # warn "-> already \e[31mresolved\e[m @{[$distribution->name]}\n";
    }
}

sub _register_fetch_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->{distfile}}++;
        return;
    }
    my $distribution = $self->distribution($job->{distfile});
    $distribution->fetched(1);
    $distribution->configure_requirements($job->{configure_requirements});
    $distribution->directory($job->{directory});
    $distribution->meta($job->{meta});
    return 1;
}

sub _register_configure_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->{distfile}}++;
        return;
    }
    my $distribution = $self->distribution($job->{distfile});
    $distribution->configured(1);
    $distribution->distdata($job->{distdata});
    $distribution->requirements($job->{requirements});
    return 1;
}

sub _register_install_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->{distfile}}++;
        return;
    }
    my $distribution = $self->distribution($job->{distfile});
    $distribution->installed(1);
    return 1;
}

1;
