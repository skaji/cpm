package App::cpm::Hook::Context;
use strict;
use warnings;
use App::cpm::Hook;

sub new {
    my $class = shift;
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
    }, $class;
}

for my $phase (qw(configure build test install)) {
    no strict 'refs';
    *{ "${phase}_args" } = sub {
        my ($self, @args) = @_;
        push @{$self->{args}{$phase}}, @args;
    };
}

for my $phase (qw(runtime configure build test)) {
    my $add = sub {
        my $self = shift;
        my %package = (@_, @_ % 2 ? (0) : ());
        $self->{requirements}{add}{$phase}{$_} = $package{$_} for keys %package;
    };
    my $delete = sub {
        my ($self, @package) = @_;
        push @{$self->{requirements}{add}{$phase}}, @package;
    };
    no strict 'refs';
    *{ "add_${phase}_requires" } = $add;
    *{ "delete_${phase}_requires" } = $delete;
}
*add_requires = *add_runtime_requires;
*delete_requires = *delete_runtime_requires;

sub pureperl_only {
    my ($self, $v) = @_;
    $self->{pureperl_only} = $v;
}

sub env {
    my ($self, %env) = @_;
    $self->{env}{$_} = $env{$_} for keys %env;
}

sub patch {
    my ($self, @patch) = @_;
    push @{$self->{patch}}, @patch;
}

sub as_hook {
    my $self = shift;
    App::cpm::Hook->new(%$self);
}

1;
