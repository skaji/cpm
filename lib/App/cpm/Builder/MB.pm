package App::cpm::Builder::MB;
use v5.24;
use warnings;
use experimental qw(signatures);

use parent 'App::cpm::Builder';

sub supports ($class, @) {
    -f 'Build.PL';
}

sub configure ($self, $ctx) {
    my @cmd = ($ctx->{perl}, 'Build.PL');
    push @cmd, "--install_base", $self->{install_base} if $self->{install_base};
    push @cmd, qw(--config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=) if $self->{need_noman_argv};
    push @cmd, '--pureperl-only' if $self->{pureperl_only};
    push @cmd, $self->{argv}->@* if $self->{argv}->@*;
    $self->run_configure($ctx, \@cmd) && -f 'Build';
}

sub build ($self, $ctx) {
    $self->run_build($ctx, [ $ctx->{perl}, "./Build" ]);
}

sub test ($self, $ctx) {
    $self->run_test($ctx, [ $ctx->{perl}, "./Build", "test" ]);
}

sub install ($self, $ctx) {
    $self->run_install($ctx, [ $ctx->{perl}, "./Build", "install" ]);
}

1;
