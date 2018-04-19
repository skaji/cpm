package App::cpm::Hook;
use strict;
use warnings;
use App::cpm::Requirement;

sub new {
    my ($class, %args) = @_;
    bless {
        args => {
            configure => [],
            build => [],
            test => [],
            install => [],
        },
        requirements => {
            add => {
                configure => {},
                build => {},
                test => {},
                install => {},
                runtime => {},
            },
            delete => {
                configure => [],
                build => [],
                test => [],
                install => [],
                runtime => [],
            },
        },
        env => {},
        patch => [],
        pureperl_only => undef,
        %args
    }, $class;
}

sub is_effective {
    my $self = shift;
    $self->{pureperl_only} and return 1;
    %{$self->{env}} and return 1;
    @{$self->{patch}} and return 1;
    for my $phase (qw(configure build test install runtime)) {
        if ($phase ne 'runtime') {
            @{$self->{args}{$phase}} and return 1;
        }
        %{$self->{requirements}{add}{$phase}} and return 1;
        @{$self->{requirements}{delete}{$phase}} and return 1;
    }
    return;
}

sub args {
    my ($self, $phase) = @_;
    @{$self->{args}{$phase}};
}

sub pureperl_only {
    my $self = shift;
    $self->{pureperl_only};
}

sub env {
    my $self = shift;
    %{$self->{env}};
}

sub patch {
    my $self = shift;
    @{$self->{patch}}
}

sub requirement {
    my ($self, $phases, $original) = @_;
    for my $phase (@$phases) {
        my $add = App::cpm::Requirement->new( %{$self->{requirements}{add}{$phase}} );
        $original->merge($add)
            or return;
    }
    for my $phase (@$phases) {
        $original->delete(@{$self->{requirements}{delete}{$phase}})
    }
    return 1;
}

1;
