package App::cpm::Master;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::CircularDependency;
use App::cpm::DependencyTracker;
use App::cpm::Distribution;
use App::cpm::Logger;
use App::cpm::Logger::Terminal;
use App::cpm::Task;
use App::cpm::version;
use CPAN::DistnameInfo;
use Module::Metadata;
use File::pushd 'pushd';

sub new ($class, %argv) {
    my $self = bless {
        %argv,
        installed_distributions => 0,
        tasks => +{},
        distributions => +{},
        dependency_tracker => App::cpm::DependencyTracker->new,
        _fail_resolve => +{},
        _fail_install => +{},
        _is_installed => +{},
    }, $class;
    if ($self->{target_perl}) {
        require Module::CoreList;
        if (!exists $Module::CoreList::version{$self->{target_perl}}) {
            die "Module::CoreList does not have target perl $self->{target_perl} entry, abort.\n";
        }
        if (!exists $Module::CoreList::version{$]}) {
            die "Module::CoreList does not have our perl $] entry, abort.\n";
        }
    }
    if (!$self->{global}) {
        if (eval { require Module::CoreList }) {
            if (!exists $Module::CoreList::version{$]}) {
                die "Module::CoreList does not have our perl $] entry, abort.\n";
            }
            $self->{_has_corelist} = 1;
        } else {
            my $msg = "You don't have Module::CoreList. "
                    . "The local-lib may result in incomplete self-contained directory.";
            App::cpm::Logger->log(result => "WARN", message => $msg);
        }
    }
    $self;
}

sub fail ($self, $ctx) {
    my @fail_resolve = sort keys $self->{_fail_resolve}->%*;
    my @fail_install = sort keys $self->{_fail_install}->%*;
    my @not_installed = grep { !$self->{_fail_install}{$_->distfile} && !$_->installed } $self->_final_install_distributions(1);
    return if !@fail_resolve && !@fail_install && !@not_installed;

    my $detector = App::cpm::CircularDependency->new;
    for my $dist (@not_installed) {
        my $req = $dist->requirements([qw(configure build test runtime)])->as_array;
        $detector->add($dist->distfile, $dist->provides, $req);
    }
    $detector->finalize;

    my $detected = $detector->detect;
    for my $distfile (sort keys $detected->%*) {
        my $distvname = $self->distribution($distfile)->distvname;
        my @circular = $detected->{$distfile}->@*;
        my $msg = join " -> ", map { $self->distribution($_)->distvname } @circular;
        local $ctx->{logger}{context} = $distvname;
        $ctx->log("Detected circular dependencies $msg");
        $ctx->log("Failed to install distribution");
    }
    for my $dist (sort { $a->distvname cmp $b->distvname } grep { !$detected->{$_->distfile} } @not_installed) {
        local $ctx->{logger}{context} = $dist->distvname;
        $ctx->log("Failed to install distribution, "
                            ."because of installing some dependencies failed");
    }

    my @fail_install_name = map { CPAN::DistnameInfo->new($_)->distvname || $_ } @fail_install;
    my @not_installed_name = map { $_->distvname } @not_installed;
    if (@fail_resolve || @fail_install_name) {
        $ctx->log("--");
        $ctx->log(
            "Installation failed. "
            . "The direct cause of the failure comes from the following packages/distributions; "
            . "you may want to grep this log file by them:"
        );
        $ctx->log(" * $_") for @fail_resolve, sort @fail_install_name;
    }
    { resolve => \@fail_resolve, install => [sort @fail_install_name, @not_installed_name] };
}

sub tasks ($self) { values $self->{tasks}->%* }

sub add_task ($self, $ctx, %task) {
    my $new = App::cpm::Task->new(%task);
    if (my ($existing) = grep { $_->equals($new) } $self->tasks) {
        $existing->{final_target} ||= $new->{final_target};
        return 0;
    } else {
        $self->{tasks}{$new->uid} = $new;
        return 1;
    }
}

sub get_task ($self, $ctx) {
    if (my @task = grep { !$_->in_charge } $self->tasks) {
        return @task;
    }
    $self->_add_tasks($ctx);
    return if !$self->tasks;
    if (my @task = grep { !$_->in_charge } $self->tasks) {
        return @task;
    }
    return;
}

sub register_result ($self, $ctx, $result) {
    my ($task) = grep { $_->uid eq $result->{uid} } $self->tasks;
    die "Missing task that has uid=$result->{uid}" if !$task;

    $task->%* = $result->%*; # XXX

    my $logged = $self->info($task);
    my $method = "_register_@{[$task->{type}]}_result";
    $self->$method($ctx, $task);
    $self->remove_task($ctx, $task);

    return 1;
}

sub info ($self, $task) {
    my $type = $task->type;
    if (!$App::cpm::Logger::VERBOSE && $task->{ok}) {
        return if !($self->{notest} && $type eq "fetch" && $task->{prebuilt})
            && !($self->{notest} && $type eq "build" && !$task->{prebuilt})
            && !(!$self->{notest} && $type eq "test");
    }
    my $name = $task->distvname;
    my ($message, $optional);
    if ($type eq "resolve") {
        $message = $task->{package};
        $message .= " -> $name" . ($task->{ref} ? "\@$task->{ref}" : "") if $task->{ok};
        $optional = "from $task->{from}" if $task->{ok} and $task->{from};
    } else {
        $message = $name;
        $optional = "using cache" if $type eq "fetch" and $task->{using_cache};
        $optional = "using prebuilt" if $task->{prebuilt};
    }
    my $elapsed = defined $task->{elapsed} ? sprintf "(%.3fsec) ", $task->{elapsed} : "";

    App::cpm::Logger->log(
        pid => $task->{pid},
        type => $type,
        result => $task->{ok} ? "DONE" : "FAIL",
        message => "$elapsed$message",
        optional => $optional,
    );
    return 1;
}

sub enable_terminal_logger ($self, %argv) {
    $self->{terminal_logger} = App::cpm::Logger::Terminal->new(%argv);
}

sub _terminal_summary_count ($self) {
    my $state = $self->{notest} ? "built" : "tested";
    scalar grep { $_->$state || $_->installed } $self->distributions;
}

sub _terminal_summary_total ($self) {
    my $distributions = scalar keys $self->{distributions}->%*;
    my $tasks = scalar keys $self->{tasks}->%*;
    $distributions > $tasks ? $distributions : $tasks;
}

sub log_task ($self) {
    my $terminal = $self->{terminal_logger};
    my $lines = $terminal->new_lines;

    for my $pid (sort { $a <=> $b } keys $terminal->{pids}->%*) {
        my ($task) = grep { ($_->in_charge || 0) == $pid } $self->tasks;
        $lines->set_worker($pid, $task);
    }

    $lines->set_summary($self->_terminal_summary_count, $self->_terminal_summary_total);
    $terminal->write($lines);
}

sub finalize_terminal_logger ($self) {
    my $terminal = delete $self->{terminal_logger};
    $terminal->finalize;
}

sub remove_task ($self, $ctx, $task) {
    delete $self->{tasks}{$task->uid};
}

sub distributions ($self) { values $self->{distributions}->%* }

sub distribution ($self, $distfile) {
    $self->{distributions}{$distfile};
}

sub install_phase_state ($self, $dist) {
    return "built" if $dist->prebuilt;
    return $self->{notest} ? "built" : "tested";
}

sub dependency_env_for ($self, $dist, $phases, $seen = undef, $found = undef) {
    $seen ||= {};
    $found ||= {};

    for my $req ($dist->requirements($phases)->as_array->@*) {
        my ($package, $version_range) = $req->@{qw(package version_range)};
        next if $package eq "perl";
        next if $self->{target_perl} and $self->is_core($package, $version_range);

        my $resolved = $self->{dependency_tracker}->resolved_distribution($package, $version_range);
        if (!$resolved) {
            next if $self->is_installed($package, $version_range);
            next;
        }
        next if !$self->{dependency_tracker}->is_dependency_ready($resolved);
        next if $seen->{$resolved->distfile}++;

        $found->{$resolved->distfile} = $resolved;
        $self->dependency_env_for($resolved, 'runtime', $seen, $found);
    }

    my (@libs, @paths);
    for my $resolved (values $found->%*) {
        push @libs, $resolved->builder->libs->@*;
        push @paths, $resolved->builder->paths->@*;
    }

    return {
        dependency_libs => \@libs,
        dependency_paths => \@paths,
    };
}

sub _final_install_distributions ($self, $include_unready = 0) {
    return grep { $include_unready || $self->{dependency_tracker}->is_dependency_ready($_) } $self->distributions
        if $self->{final_install} eq "all";

    my %seen;
    my @todo = grep { $_->final_target } $self->distributions;
    my @install;
    while (my $dist = shift @todo) {
        next if $seen{$dist->distfile}++;
        push @install, $dist if $include_unready || $self->{dependency_tracker}->is_dependency_ready($dist);

        for my $req ($dist->requirements('runtime')->as_array->@*) {
            my ($package, $version_range) = $req->@{qw(package version_range)};
            next if $package eq "perl";
            next if $self->{target_perl} and $self->is_core($package, $version_range);

            my $resolved = $self->{dependency_tracker}->resolved_distribution($package, $version_range);
            next if !$resolved;
            next if $self->is_installed($package, $version_range);
            push @todo, $resolved;
        }
    }
    return @install;
}

sub install_distributions ($self, $ctx) {
    my @dist = $self->_final_install_distributions;
    return if !@dist;

    warn "Installing distributions...\n" if $self->{progress} eq "plain" && !$App::cpm::Logger::VERBOSE;
    $ctx->log("Installing distributions");

    for my $dist (sort { $a->distvname cmp $b->distvname } @dist) {
        my $guard = pushd $dist->directory;

        local $ctx->{logger}{context} = $dist->distvname;
        $ctx->log("Installing distribution");
        my $env = $dist->builder->needs_install_env
            ? $self->dependency_env_for($dist, [qw(configure build runtime)])
            : { dependency_libs => [], dependency_paths => [] };
        my $ok = $dist->builder->install($ctx, $env->{dependency_libs}, $env->{dependency_paths});
        if ($ok) {
            $dist->installed(1);
            $self->{installed_distributions}++;
            $ctx->log("Successfully installed distribution");
            if ($App::cpm::Logger::VERBOSE || $self->{progress} eq "tty") {
                App::cpm::Logger->log(
                    type => "install",
                    result => "DONE",
                    message => $dist->distvname,
                    ($dist->prebuilt ? (optional => "using prebuilt") : ()),
                );
            }
        } else {
            $self->{_fail_install}{$dist->distfile}++;
            $ctx->log("Failed to install distribution");
            App::cpm::Logger->log(
                type => "install",
                result => "FAIL",
                message => $dist->distvname,
                ($dist->prebuilt ? (optional => "using prebuilt") : ()),
            );
        }
    }
    return 1;
}

sub _add_tasks ($self, $ctx) {
    while (1) {
        my $changed = 0;

        if ($self->{notest}) {
            $changed += $self->_mark_built_dependency_ready($ctx);
        } else {
            $changed += $self->_mark_tested_dependency_ready($ctx);
        }

        $changed += $self->_add_fetch_tasks($ctx);
        $changed += $self->_add_configure_tasks($ctx);
        $changed += $self->_add_build_tasks($ctx);

        if (!$self->{notest}) {
            $changed += $self->_add_test_tasks($ctx);
        }

        last if !$changed;
    }
}

sub _mark_built_dependency_ready ($self, $ctx) {
    my $changed = 0;
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    if (my @dists = grep { $_->built && !$self->{dependency_tracker}->is_dependency_ready($_) } @distributions) {
        for my $dist (@dists) {
            my $dependency_tracker = $self->{dependency_tracker};
            if ($dependency_tracker->has_runtime_dependency_waiting($dist) && !$dependency_tracker->is_runtime_dependency_dirty($dist)) {
                next;
            }
            my $dist_requirements = $dist->requirements('runtime')->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dependency_tracker->clear_runtime_dependency_waiting($dist);
                $self->{dependency_tracker}->mark_dependency_ready($dist);
                $changed++;
            } elsif (!defined $is_satisfied) {
                $dependency_tracker->clear_runtime_dependency_waiting($dist);
                local $ctx->{logger}{context} = $dist->distvname;
                my ($req) = grep { $_->{package} eq "perl" } $dist_requirements->@*;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $ctx->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
                $changed++;
            } elsif (@need_resolve and !$dist->deps_registered) {
                local $ctx->{logger}{context} = $dist->distvname;
                $dist->deps_registered(1);
                my $msg = sprintf "Found runtime prerequisites: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 } @need_resolve);
                $ctx->log($msg);
                my $ok = $self->_register_resolve_task($ctx, @need_resolve);
                $self->{_fail_install}{$dist->distfile}++ if !$ok;
                $dependency_tracker->remember_runtime_dependency_waiting($dist, $self->_runtime_dependency_waiting_for($dist_requirements));
                $changed++;
            } else {
                $dependency_tracker->remember_runtime_dependency_waiting($dist, $self->_runtime_dependency_waiting_for($dist_requirements));
            }
        }
    }
    return $changed;
}

sub _runtime_dependency_waiting_for ($self, $requirements) {
    my (%waiting_distfiles, %waiting_packages);
    for my $req ($requirements->@*) {
        my ($package, $version_range) = $req->@{qw(package version_range)};
        next if $package eq "perl";
        next if $self->{target_perl} and $self->is_core($package, $version_range);

        my $resolved = $self->{dependency_tracker}->resolved_distribution($package, $version_range);
        if ($resolved) {
            next if $self->{dependency_tracker}->is_dependency_ready($resolved);
            $waiting_distfiles{$resolved->distfile} = 1;
        } else {
            next if $self->is_installed($package, $version_range);
            $waiting_packages{$package} = 1;
        }
    }
    (\%waiting_distfiles, \%waiting_packages);
}

sub _mark_tested_dependency_ready ($self, $ctx) {
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    my @dists = grep { $_->tested && !$self->{dependency_tracker}->is_dependency_ready($_) } @distributions;
    $self->{dependency_tracker}->mark_dependency_ready($_) for @dists;
    return scalar @dists;
}

sub _add_fetch_tasks ($self, $ctx) {
    my $changed = 0;
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    if (my @dists = grep { $_->resolved && !$_->registered } @distributions) {
        for my $dist (@dists) {
            $dist->registered(1);
            $self->add_task(
                $ctx,
                type => "fetch",
                distfile => $dist->{distfile},
                source => $dist->source,
                uri => $dist->uri,
                ref => $dist->ref,
            );
            $changed++;
        }
    }
    return $changed;
}

sub _add_configure_tasks ($self, $ctx) {
    my $changed = 0;
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    if (my @dists = grep { $_->fetched && !$_->registered } @distributions) {
        my @phase = qw(configure);
        for my $dist (@dists) {
            local $ctx->{logger}{context} = $dist->distvname;
            my $dist_requirements = $dist->requirements(\@phase)->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                my $env = $self->dependency_env_for($dist, \@phase);
                $self->add_task(
                    $ctx,
                    type => "configure",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    provides => $dist->provides,
                    source => $dist->source,
                    uri => $dist->uri,
                    distvname => $dist->distvname,
                    $env->%*,
                );
                $changed++;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } $dist_requirements->@*;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $ctx->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
                $changed++;
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                my $msg = sprintf "Found configure dependencies: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 } @need_resolve);
                $ctx->log($msg);
                my $ok = $self->_register_resolve_task($ctx, @need_resolve);
                $self->{_fail_install}{$dist->distfile}++ if !$ok;
                $changed++;
            }
        }
    }
    return $changed;
}

sub _add_build_tasks ($self, $ctx) {
    my $changed = 0;
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    if (my @dists = grep { $_->configured && !$_->registered } @distributions) {
        my @phase = qw(configure runtime build);
        for my $dist (@dists) {
            local $ctx->{logger}{context} = $dist->distvname;
            my $dist_requirements = $dist->requirements(\@phase)->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                my $env = $self->dependency_env_for($dist, \@phase);
                $self->add_task(
                    $ctx,
                    type => "build",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    uri => $dist->uri,
                    builder => $dist->builder,
                    provides => $dist->provides,
                    $env->%*,
                );
                $changed++;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } $dist_requirements->@*;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $ctx->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
                $changed++;
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                my $msg = sprintf "Found build prerequisites: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 } @need_resolve);
                $ctx->log($msg);
                my $ok = $self->_register_resolve_task($ctx, @need_resolve);
                $self->{_fail_install}{$dist->distfile}++ if !$ok;
                $changed++;
            }
        }
    }
    return $changed;
}

sub _add_test_tasks ($self, $ctx) {
    my $changed = 0;
    my @distributions = grep { !$self->{_fail_install}{$_->distfile} } $self->distributions;
    if (my @dists = grep { $_->built && !$_->registered } @distributions) {
        for my $dist (@dists) {
            local $ctx->{logger}{context} = $dist->distvname;
            my @phase = qw(configure build runtime test);
            my $dist_requirements = $dist->requirements(\@phase)->as_array;
            my ($is_satisfied, @need_resolve) = $self->is_satisfied($dist_requirements);
            if ($is_satisfied) {
                $dist->registered(1);
                my $env = $self->dependency_env_for($dist, \@phase);
                $self->add_task(
                    $ctx,
                    type => "test",
                    meta => $dist->meta,
                    directory => $dist->directory,
                    distfile => $dist->{distfile},
                    uri => $dist->uri,
                    builder => $dist->builder,
                    provides => $dist->provides,
                    $env->%*,
                );
                $changed++;
            } elsif (!defined $is_satisfied) {
                my ($req) = grep { $_->{package} eq "perl" } $dist_requirements->@*;
                my $msg = sprintf "%s requires perl %s, but you have only %s",
                    $dist->distvname, $req->{version_range}, $self->{target_perl} || $];
                $ctx->log($msg);
                App::cpm::Logger->log(result => "FAIL", message => $msg);
                $self->{_fail_install}{$dist->distfile}++;
                $changed++;
            } elsif (@need_resolve and !$dist->deps_registered) {
                $dist->deps_registered(1);
                my $msg = sprintf "Found test prerequisites: %s",
                    join(", ", map { sprintf "%s (%s)", $_->{package}, $_->{version_range} || 0 } @need_resolve);
                $ctx->log($msg);
                my $ok = $self->_register_resolve_task($ctx, @need_resolve);
                $self->{_fail_install}{$dist->distfile}++ if !$ok;
                $changed++;
            }
        }
    }
    return $changed;
}

sub _register_resolve_task ($self, $ctx, @package) {
    my $ok = 1;
    for my $package (@package) {
        if ($self->{_fail_resolve}{$package->{package}}
            || $self->{_fail_install}{$package->{package}}
        ) {
            $ok = 0;
            next;
        }

        $self->add_task(
            $ctx,
            type => "resolve",
            package => $package->{package},
            version_range => $package->{version_range},
        );
    }
    return $ok;
}

sub is_satisfied_perl_version ($self, $version_range) {
    App::cpm::version->parse($self->{target_perl} || $])->satisfy($version_range);
}

sub is_installed ($self, $package, $version_range) {
    my $wantarray = wantarray;
    if (exists $self->{_is_installed}{$package}) {
        if ($self->{_is_installed}{$package}->satisfy($version_range)) {
            return $wantarray ? (1, $self->{_is_installed}{$package}) : 1;
        }
    }
    my $info = Module::Metadata->new_from_module($package, inc => $self->{search_inc});
    return if !$info;

    if (!$self->{global} and $self->{_has_corelist} and $self->_in_core_inc($info->filename)) {
        # https://github.com/miyagawa/cpanminus/blob/7b574ede70cebce3709743ec1727f90d745e8580/Menlo-Legacy/lib/Menlo/CLI/Compat.pm#L1783-L1786
        # if found package in core inc,
        # but it does not list in CoreList,
        # we should treat it as not being installed
        return if !exists $Module::CoreList::version{$]}{$info->name};
    }
    my $current_version = $self->{_is_installed}{$package}
                        = App::cpm::version->parse($info->version);
    my $ok = $current_version->satisfy($version_range);
    $wantarray ? ($ok, $current_version) : $ok;
}

sub _in_core_inc ($self, $file) {
    !!grep { $file =~ /^\Q$_/ } $self->{core_inc}->@*;
}

sub is_core ($self, $package, $version_range) {
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
        return 1 if !$version_range;
        my $core_version = $Module::CoreList::version{$target_perl}{$package};
        return App::cpm::version->parse($core_version)->satisfy($version_range);
    }
    return;
}

# 0:     not satisfied, need wait for satisfying requirements
# 1:     satisfied
# undef: not satisfied because of perl version
sub is_satisfied ($self, $requirements) {
    my $is_satisfied = 1;
    my @need_resolve;
    for my $req ($requirements->@*) {
        my ($package, $version_range) = $req->@{qw(package version_range)};
        if ($package eq "perl") {
            $is_satisfied = undef if !$self->is_satisfied_perl_version($version_range);
            next;
        }
        next if $self->{target_perl} and $self->is_core($package, $version_range);
        my $resolved = $self->{dependency_tracker}->resolved_distribution($package, $version_range);
        if ($resolved) {
            next if $self->{dependency_tracker}->is_dependency_ready($resolved);
        } else {
            next if $self->is_installed($package, $version_range);
        }

        $is_satisfied = 0 if defined $is_satisfied;
        if (!$resolved) {
            push @need_resolve, $req;
        }
    }
    return ($is_satisfied, @need_resolve);
}

sub add_distribution ($self, $distribution) {
    my $distfile = $distribution->distfile;
    if (my $already = $self->{distributions}{$distfile}) {
        $self->{dependency_tracker}->add_provides($already, $distribution->provides);
        $self->{dependency_tracker}->mark_resolved_packages(map { $_->{package} } $distribution->provides->@*);
        if ($already->resolved) {
            $already->overwrite_provide($_) for $distribution->provides->@*;
        }
        return 0;
    } else {
        $self->{distributions}{$distfile} = $distribution;
        $self->{dependency_tracker}->add_provides($distribution, $distribution->provides);
        $self->{dependency_tracker}->mark_resolved_packages(map { $_->{package} } $distribution->provides->@*);
        return 1;
    }
}

sub _register_resolve_result ($self, $ctx, $task) {
    if (!$task->is_success) {
        $self->{_fail_resolve}{$task->{package}}++;
        return;
    }

    local $ctx->{logger}{context} = $task->{package};
    if ($task->{distfile} and $task->{distfile} =~ m{/perl-5[^/]+$}) {
        my $message = "$task->{package} is a core module.";
        $ctx->log($message);
        App::cpm::Logger->log(
            result => "DONE",
            type => "install",
            message => $message,
        );
        return;
    }

    if (!$task->{reinstall}) {
        my $want = $task->{version_range} || $task->{version};
        my ($ok, $local) = $self->is_installed($task->{package}, $want);
        if ($ok) {
            my $message = $task->{package} . (
                App::cpm::version->parse($task->{version}) != $local
                ? ", you already have $local"
                : " is up to date. ($local)"
            );
            $ctx->log($message);
            App::cpm::Logger->log(
                result => "DONE",
                type => "install",
                message => $message,
            );
            return;
        }
    }

    my $provides = $task->{provides};
    if (!$provides or $provides->@* == 0) {
        my $version = App::cpm::version->parse($task->{version}) || 0;
        $provides = [{package => $task->{package}, version => $version}];
    }
    my $distribution = App::cpm::Distribution->new(
        source   => $task->{source},
        uri      => $task->{uri},
        provides => $provides,
        distfile => $task->{distfile},
        ref      => $task->{ref},
        final_target => $task->{final_target},
    );
    if (!$self->add_distribution($distribution) && $task->{final_target}) {
        $self->distribution($distribution->distfile)->final_target(1);
    }
}

sub _register_fetch_result ($self, $ctx, $task) {
    if (!$task->is_success) {
        $self->{_fail_install}{$task->distfile}++;
        return;
    }
    my $distribution = $self->distribution($task->distfile);
    $distribution->directory($task->{directory});
    $distribution->meta($task->{meta});
    $distribution->provides($task->{provides});

    if ($task->{prebuilt}) {
        $distribution->built(1);
        $distribution->requirements($_ => $task->{requirements}{$_}) for keys $task->{requirements}->%*;
        $distribution->builder($task->{builder});
        $distribution->prebuilt(1);
    } else {
        $distribution->fetched(1);
        $distribution->requirements($_ => $task->{requirements}{$_}) for keys $task->{requirements}->%*;
    }
    local $ctx->{logger}{context} = $distribution->distvname;
    my $msg = join ", ", map { sprintf "%s (%s)", $_->{package}, $_->{version} || 0 } $distribution->provides->@*;
    $ctx->log("Distribution provides: $msg");
    return 1;
}

sub _register_configure_result ($self, $ctx, $task) {
    if (!$task->is_success) {
        $self->{_fail_install}{$task->distfile}++;
        return;
    }
    my $distribution = $self->distribution($task->distfile);
    $distribution->configured(1);
    $distribution->requirements($_ => $task->{requirements}{$_}) for keys $task->{requirements}->%*;
    $distribution->builder($task->{builder});
    return 1;
}

sub _register_build_result ($self, $ctx, $task) {
    if (!$task->is_success) {
        $self->{_fail_install}{$task->distfile}++;
        return;
    }
    my $distribution = $self->distribution($task->distfile);
    $distribution->built(1);
    $distribution->builder($task->{builder});
    return 1;
}

sub _register_test_result ($self, $ctx, $task) {
    if (!$task->is_success) {
        $self->{_fail_install}{$task->distfile}++;
        return;
    }
    my $distribution = $self->distribution($task->distfile);
    $distribution->tested(1);
    return 1;
}

sub installed_distributions ($self) { $self->{installed_distributions} }

1;
