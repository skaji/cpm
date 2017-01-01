package App::cpm::Master;
use strict;
use warnings;
use utf8;
use App::cpm::Distribution;
use App::cpm::Job;
use App::cpm::Logger;
use Module::CoreList;
use Module::Metadata;
use version;
our $VERSION = '0.297';

sub new {
    my ($class, %option) = @_;
    if (!exists $Module::CoreList::version{$]}) {
        die "Module::CoreList does not have your perl $^V entry, abort.\n";
    }
    bless {
        %option,
        installed_distributions => 0,
        jobs => +{},
        distributions => +{},
        _fail_resolve => +{},
        _fail_install => +{},
        _is_installed => +{},
    }, $class;
}

sub fail {
    my $self = shift;
    my @fail_resolve = sort keys %{$self->{_fail_resolve}};
    my @fail_install = sort keys %{$self->{_fail_install}};
    return if !@fail_resolve && !@fail_install;
    my @name = map { CPAN::DistnameInfo->new($_)->distvname || $_ } @fail_install;
    { resolve => \@fail_resolve, install => \@name };
}

sub jobs { values %{shift->{jobs}} }

sub add_job {
    my ($self, %job) = @_;
    my $new = App::cpm::Job->new(%job);
    if (grep { $_->equals($new) } $self->jobs) {
        return 0;
    } else {
        $self->{jobs}{$new->uid} = $new;
        return 1;
    }
}

sub get_job {
    my $self = shift;
    if (my @job = grep { !$_->in_charge } $self->jobs) {
        return @job;
    }
    $self->_calculate_jobs;
    return unless $self->jobs;
    if (my @job = grep { !$_->in_charge } $self->jobs) {
        return @job;
    }
    return;
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

    if (my @dists = grep { $_->resolved && !$_->registered } @distributions) {
        for my $dist (@dists) {
            $dist->registered(1);
            $self->add_job(
                type => "fetch",
                distfile => $dist->{distfile},
                source => $dist->source,
                uri => $dist->uri,
                ref => $dist->ref,
            );
        }
    }

    if (my @dists = grep { $_->fetched && !$_->registered } @distributions) {
        for my $dist (@dists) {
            my ($is_satisfied, @need_resolve)
                = $self->is_satisfied($dist->configure_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                $self->add_job(
                    type => "configure",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    source => $dist->source,
                    uri => $dist->uri,
                );
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                local $self->{logger}->{context} = $dist->distvname;
                my $msg = sprintf "Found configure dependencies: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 }  @need_resolve);
                $self->{logger}->log($msg);
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } @{$dist->configure_requirements};
                my $msg = sprintf "%s requires perl %s", $dist->distvname, $req->{version_range};
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
            }
        }
    }

    if (my @dists = grep { $_->configured && !$_->registered } @distributions) {
        for my $dist (@dists) {
            my ($is_satisfied, @need_resolve)
                = $self->is_satisfied($dist->requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                $self->add_job(
                    type => "install",
                    meta => $dist->meta,
                    distdata => $dist->distdata,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    uri => $dist->uri,
                    static_builder => $dist->static_builder,
                );
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                local $self->{logger}->{context} = $dist->distvname;
                my $msg = sprintf "Found dependencies: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 }  @need_resolve);
                $self->{logger}->log($msg);
                my $ok = $self->_register_resolve_job(@need_resolve);
                $self->{_fail_install}{$dist->distfile}++ unless $ok;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } @{$dist->configure_requirements};
                my $msg = sprintf "%s requires perl %s", $dist->distvname, $req->{version_range};
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
            }
        }
    }
}

sub _register_resolve_job {
    my ($self, @package) = @_;
    my $ok = 1;
    for my $package (@package) {
        if ($self->{_fail_resolve}{$package->{package}}
            || $self->{_fail_install}{$package->{package}}
        ) {
            $ok = 0;
            next;
        }

        $self->add_job(
            type => "resolve",
            package => $package->{package},
            version_range => $package->{version_range},
        );
    }
    return $ok;
}

sub is_satisfied_perl_version {
    my ($self, $version_range) = @_;
    App::cpm::version->parse($self->{target_perl} || $])->satisfy($version_range);
}

sub is_installed {
    my ($self, $package, $version_range) = @_;
    if (exists $self->{_is_installed}{$package}) {
        return 1 if $self->{_is_installed}{$package}->satisfy($version_range);
    }
    my $info = Module::Metadata->new_from_module($package, inc => $self->{inc});
    return unless $info;
    my $current_version = $self->{_is_installed}{$package}
                        = App::cpm::version->parse($info->version);
    return $current_version->satisfy($version_range);
}

sub is_core {
    my ($self, $package, $version_range) = @_;
    my $target_perl = $self->{target_perl};
    if (exists $Module::CoreList::version{$target_perl}{$package}) {
        if (!exists $Module::CoreList::version{$]}{$package}) {
            if (!$self->{_removed_core}{$package}++) {
                my $t = App::cpm::version->parse($target_perl)->normal;
                my $v = App::cpm::version->parse($])->normal;
                App::cpm::Logger->log(
                    result => "WARN",
                    message => "$package used to be core in $t, but not in $v, so will be installed",
                );
            }
            return;
        }
        return 1 unless $version_range;
        my $core_version = $Module::CoreList::version{$target_perl}{$package};
        return App::cpm::version->parse($core_version)->satisfy($version_range);
    }
    return;
}

# 0:     not satisfied, need wait for satisfying requirements
# 1:     satisfied, ready to install
# undef: not satisfied because of perl version
sub is_satisfied {
    my ($self, $requirements) = @_;
    my $is_satisfied = 1;
    my @need_resolve;
    my @distributions = $self->distributions;
    for my $req (@$requirements) {
        my ($package, $version_range) = @{$req}{qw(package version_range)};
        if ($package eq "perl") {
            $is_satisfied = undef if !$self->is_satisfied_perl_version($version_range);
            next;
        }
        next if $self->{target_perl} and $self->is_core($package, $version_range);
        next if $self->is_installed($package, $version_range);
        my ($resolved) = grep { $_->providing($package, $version_range) } @distributions;
        next if $resolved && $resolved->installed;

        $is_satisfied = 0 if defined $is_satisfied;
        if (!$resolved) {
            push @need_resolve, $req;
        }
    }
    return ($is_satisfied, @need_resolve);
}

sub add_distribution {
    my ($self, $distribution) = @_;
    my $distfile = $distribution->distfile;
    if (my $already = $self->{distributions}{$distfile}) {
        $already->overwrite_provide($_) for @{ $distribution->provides };
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
    if ($job->{distfile} and $job->{distfile} =~ m{/perl-5[^/]+$}) {
        App::cpm::Logger->log(
            result => "FAIL",
            type => "install",
            message => "Cannot upgrade core module $job->{package}.",
        );
        $self->{_fail_install}{$job->{package}}++; # XXX
        return;
    }

    if ($self->is_installed($job->{package}, "== $job->{version}")) { # XXX
        my $version = $job->{version} || 0;
        App::cpm::Logger->log(
            result => "DONE",
            type => "install",
            message => "$job->{package} is up to date. ($version)",
        );
        return;
    }

    my $provides = $job->{provides};
    if (!$provides or @$provides == 0) {
        my $version = App::cpm::version->parse($job->{version}) || 0;
        $provides = [{package => $job->{package}, version => $version}];
    }
    my $distribution = App::cpm::Distribution->new(
        source   => $job->{source},
        uri      => $job->{uri},
        provides => $provides,
        distfile => $job->{distfile},
    );
    $self->add_distribution($distribution);
}

sub _register_fetch_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->fetched(1);
    $distribution->configure_requirements($job->{configure_requirements});
    $distribution->directory($job->{directory});
    $distribution->meta($job->{meta});
    $distribution->provides($job->{provides});
    return 1;
}

sub _register_configure_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->configured(1);
    $distribution->distdata($job->{distdata});
    $distribution->requirements($job->{requirements});
    $distribution->static_builder($job->{static_builder});
    return 1;
}

sub _register_install_result {
    my ($self, $job) = @_;
    if (!$job->is_success) {
        $self->{_fail_install}{$job->distfile}++;
        return;
    }
    my $distribution = $self->distribution($job->distfile);
    $distribution->installed(1);
    $self->{installed_distributions}++;
    return 1;
}

sub installed_distributions {
    shift->{installed_distributions};
}

1;
