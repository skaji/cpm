package Acme::CPAN::Installer::Master;
use strict;
use warnings;
use utf8;
use Acme::CPAN::Installer::Distribution;
use Acme::CPAN::Installer::Job;
use IO::Handle;
use IO::Select;
use JSON::PP;
use Scalar::Util qw(weaken);
use List::Util qw(all);

sub new {
    my $class = shift;
    bless {
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
        Acme::CPAN::Installer::_Worker;
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
        sysread $self->read_fh, my $buffer, 64*1024;
        decode_json $buffer;
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
    $self->{workers}{$pid} = Acme::CPAN::Installer::_Worker->new(
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
        if (grep { $worker->read_fh == $_  } @ready) {
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
    my $new = Acme::CPAN::Installer::Job->new(%job);
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

    $job->{result} = $result->{result};
    if ($job->type eq "resolve") {
        $self->_register_resolve_result($job);
    } elsif ($job->type eq "install") {
        $self->_register_install_result($job);
    }
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

    my @all = $self->distributions;
    my @not_installed
        = grep { !$_->installed && !$self->{_fail_install}{$_->distfile} } @all;

    for my $dist (@not_installed) {
        my $ready_to_install = 1;
        for my $req (@{$dist->requirements}) {
            my ($package, $version) = @{$req}{qw(package version)};

            next if Acme::CPAN::Installer::Distribution->is_core($package, $version);

            if ($self->{_fail_resolve}{$package}) {
                $ready_to_install = 0;
                $self->{_fail_install}{$dist->distfile}++;
                next;
            }

            my ($resolved) = grep { $_->providing($package, $version) } @all;
            next if $resolved && $resolved->installed;
            $ready_to_install = 0;
            if (!$resolved) {
                my $added = $self->add_job(
                    type => "resolve",
                    package => $package,
                    version => $version,
                );
                if ($added) {
                    # warn "-> stack \e[35mresolve\e[m $package (from @{[$dist->name]})\n";
                }
            }
        }

        if ($ready_to_install) {
            my $added = $self->add_job(
                type => "install",
                distfile => $dist->distfile,
            );
            if ($added) {
                # warn "-> stack \e[36minstall\e[m @{[$dist->name]}\n";
            }
        }
    }
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

    my $distribution = Acme::CPAN::Installer::Distribution->new(
        distfile => $job->result->{distfile},
        provides => $job->result->{provides},
        requirements => $job->result->{requirements},
    );
    my $added = $self->add_distribution($distribution);
    unless ($added) {
        # warn "-> already \e[31mresolved\e[m @{[$distribution->name]}\n";
    }
}

sub _register_install_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->{distfile}}++;
        return;
    }
    $self->distribution($job->{distfile})->installed(1);
    return 1;
}


1;
