package App::cpm2::Master;
use strict;
use warnings;

use App::cpm2::Task;
use App::cpm2::Distribution;
use Config;
use Module::Metadata;

sub new {
    my $class = shift;
    bless {
        inc => [@Config{qw(archlibexp privlibexp)}],
        task => {},
        distribution => {},
    }, $class;
}

sub distributions {
    my $self = shift;
    values %{$self->{distribution}};
}

sub distribution {
    my ($self, $disturl) = @_;
    $self->{distribution}{$disturl};
}

sub add_task {
    my $self = shift;
    my $task = App::cpm2::Task->new(@_);
    $self->{task}{$task->id} = $task if !exists $self->{task}{$task->id};
}

sub get_task {
    my $self = shift;
    if (my @task = grep { !$_->running } values %{$self->{task}}) {
        return @task;
    }
    $self->calculate_task;
    if (my @task = grep { !$_->running } values %{$self->{task}}) {
        return @task;
    }
    return;
}

sub calculate_task {
    my $self = shift;

    my @dist = values %{$self->{distribution}};

    for my $dist (grep { $_->resolved && !$_->registerd } @dist) {
        $dist->registerd(1);
        $self->add_task(type => "fetch", distribution => $dist);
    }

    for my $dist (grep { $_->fetched && !$_->registerd } @dist) {
        my @requirement = $dist->requirement(['configure']);
        my ($ok, $dependencies, $missings) = $self->satisfied(@requirement);
        if ($ok) {
            $dist->registerd(1);
            $dist->dependencies(configure => $dependencies);
            $self->add_job(type => 'configure', distribution => $dist);
        }
        for my $missing (@$missings) {
            $self->add_job(
                type => 'resolve',
                package => $missing->{package},
                version_range => $missing->{version_range},
            );
        }
    }

    for my $dist (grep { $_->configured && !$_->registerd } @dist) {
        my @requirement = $dist->requirement(['build']);
        my ($ok, $dependencies, $missings) = $self->satisfied(@requirement);
        if ($ok) {
            $dist->registerd(1);
            $dist->dependencies(build => $dependencies);
            $self->add_job(type => 'build', distribution => $dist);
        }
        for my $missing (@$missings) {
            $self->add_job(
                type => 'resolve',
                package => $missing->{package},
                version_range => $missing->{version_range},
            );
        }
    }

    for my $dist (grep { $_->built && !$_->registerd } @dist) {
        my @requirement = $dist->requirement(['runtime']);
        my ($ok, $dependencies, $missings) = $self->satisfied(@requirement);
        if ($ok) {
            $dist->ready(1);
            $dist->dependencies(runtime => $dependencies);
        }
        for my $missing (@$missings) {
            $self->add_job(
                type => 'resolve',
                package => $missing->{package},
                version_range => $missing->{version_range},
            );
        }
    }
}

sub satisfied {
    my ($self, @requirement) = @_;

    my @dist = $self->distributions;

    my $ok = 1;
    my (@dependency, @missing);
    for my $requirement (@requirement) {
        if ($requirement->{package} eq 'perl') {
            next;
        }
        if ($self->in_inc($requirement)) {
            next;
        }
        if (my ($providing) = grep { $_->providing($requirement) } @dist) {
            if ($providing->ready) {
                push @dependency, $providing;
                next;
            } else {
                $ok = 0;
                next;
            }
        }
        push @missing, $requirement;
        $ok = 0;
    }
    ($ok, \@dependency, \@missing);
}

sub in_inc {
    my ($self, $requirement) = @_;
    my $metadata = Module::Metadata->new_from_module($requirement->{package}, inc => $self->{inc});
    return if !$metadata;
    1;
}

sub register_result {
    my ($self, $result) = @_;

    my $task = delete $self->{task}{$result->{id}} or die;

    if ($task->type eq 'resolve') {
        if ($result->{err}) {
            $self->{fail}{package}{$result->{package}} = $result->{err};
            return;
        } else {
            my $dist = App::cpm2::Distribution->new;
            $dist->disturl($result->{disturl});
            $self->{distribution}{$dist->disturl} = $dist;
            return;
        }
    }

    if ($result->{err}) {
        $self->{fail}{distribution}{$result->{disturl}} = $result->{err};
        return;
    }

    my $dist = $self->{distribution}{$result->{disturl}} or die;
    if ($task->type eq 'fetch') {
        $dist->fetched(1);
        $dist->provides($result->{provides});
        $dist->requires(%{$result->{requires}});
        return;
    }
    if ($task->type eq 'configure') {
        $dist->configured(1);
        $dist->requires(%{$result->{requires}});
        return;
    }
    if ($task->type eq 'build') {
        $dist->built(1);
        return;
    }
    die;
}

1;
