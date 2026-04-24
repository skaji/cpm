package App::cpm::Builder::EUMM;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Builder::Base';

sub supports ($class, @) {
    -f 'Makefile.PL';
}

sub configure ($self, $ctx, $dependency_libs, $dependency_paths) {
    if (!$ctx->{make}) {
        $ctx->log("There is Makefile.PL, but you don't have 'make' command; you should install 'make' command first");
        return;
    }
    my @cmd = ($ctx->{perl}, 'Makefile.PL');
    push @cmd, "INSTALL_BASE=$self->{install_base}" if $self->{install_base};
    push @cmd, qw(INSTALLMAN1DIR=none INSTALLMAN3DIR=none) if $self->{need_noman_argv};
    push @cmd, 'PUREPERL_ONLY=1' if $self->{pureperl_only};
    push @cmd, $self->{argv}->@* if $self->{argv}->@*;
    $self->run_configure($ctx, \@cmd, $dependency_libs, $dependency_paths) && -f 'Makefile';
}

sub build ($self, $ctx, $dependency_libs, $dependency_paths) {
    my $ok = $self->run_build($ctx, [ $ctx->{make} ], $dependency_libs, $dependency_paths);
    return if !$ok;
    $self->_prepare_paths_cache;
    $self->_write_blib_meta($ctx);
    return 1;
}

sub test ($self, $ctx, $dependency_libs, $dependency_paths) {
    $self->run_test($ctx, [ $ctx->{make}, "test" ], $dependency_libs, $dependency_paths);
}

1;
