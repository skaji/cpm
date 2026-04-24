package App::cpm::Builder::MB;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Builder::Base';

sub supports ($class, @) {
    -f 'Build.PL';
}

sub configure ($self, $ctx, $dependency_libs, $dependency_paths) {
    my @cmd = ($ctx->{perl}, 'Build.PL');
    push @cmd, "--install_base", $self->{install_base} if $self->{install_base};
    push @cmd, qw(--config installman1dir= --config installsiteman1dir= --config installman3dir= --config installsiteman3dir=) if $self->{need_noman_argv};
    push @cmd, '--pureperl-only' if $self->{pureperl_only};
    push @cmd, $self->{argv}->@* if $self->{argv}->@*;
    $self->run_configure($ctx, \@cmd, $dependency_libs, $dependency_paths) && -f 'Build';
}

sub build ($self, $ctx, $dependency_libs, $dependency_paths) {
    my $ok = $self->run_build($ctx, [ $ctx->{perl}, "./Build" ], $dependency_libs, $dependency_paths);
    return if !$ok;
    $self->_prepare_paths_cache;
    $self->_write_blib_meta($ctx);
    return 1;
}

sub test ($self, $ctx, $dependency_libs, $dependency_paths) {
    $self->run_test($ctx, [ $ctx->{perl}, "./Build", "test" ], $dependency_libs, $dependency_paths);
}

sub install ($self, $ctx, $dependency_libs, $dependency_paths) {
    my $ok = $self->run_install($ctx, [ $ctx->{perl}, "./Build", "install" ], $dependency_libs, $dependency_paths);
    return if !$ok;
    $self->_install_blib_meta($ctx);
    return 1;
}

1;
