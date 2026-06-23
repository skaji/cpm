package App::cpm::Builder::EUMM;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Builder::Base';

sub supports ($class, @) {
    -f 'Makefile.PL';
}

sub _makefile_pl_has_postamble ($self) {
    return 0 if !-f 'Makefile.PL';
    open my $fh, '<', 'Makefile.PL' or return 0;
    while (my $line = <$fh>) {
        return 1 if $line =~ /MY::install|postamble/;
    }
    return 0;
}

sub configure ($self, $ctx, $dependency_libs, $dependency_paths) {
    if (!$ctx->{make}) {
        $ctx->log("There is Makefile.PL, but you don't have 'make' command; you should install 'make' command first");
        return;
    }
    # Pre-detect postamble before Makefile.PL runs so INSTALL_BASE is passed
    # when this distribution will need 'make install' rather than blib copy.
    $self->{_needs_install_command} = $self->_makefile_pl_has_postamble;
    my @cmd = ($ctx->{perl}, 'Makefile.PL');
    push @cmd, "INSTALL_BASE=$self->{install_base}"
        if $self->{install_base} && ($self->{use_install_command} || $self->{_needs_install_command});
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

# Detect whether the generated Makefile has a custom install target with
# additional dependencies — i.e. a MY::install postamble. If so, we must
# run 'make install' rather than copying from blib/ directly, otherwise
# the postamble's actions (e.g. XML::SAX's install_sax_driver writing
# ParserDetails.ini, DBD driver registration, etc.) are silently skipped.
sub _has_install_postamble ($self) {
    return 0 if !-f 'Makefile';
    open my $fh, '<', 'Makefile' or return 0;
    while (my $line = <$fh>) {
        # A custom install target with extra prerequisites looks like:
        #   install :: pure_install doc_install install_sax_driver
        # i.e. the install target has dependencies beyond the standard ones.
        return 1 if $line =~ /^install\s*:.*\binstall_/;
    }
    return 0;
}

sub install ($self, $ctx, $dependency_libs = [], $dependency_paths = []) {
    if (!$self->{use_install_command} && !$self->{_needs_install_command} && !$self->_has_install_postamble) {
        return $self->SUPER::install($ctx, $dependency_libs, $dependency_paths);
    }
    my $ok = $self->run_install($ctx, [ $ctx->{make}, "install" ], $dependency_libs, $dependency_paths);
    return if !$ok;
    $self->_install_blib_meta($ctx);
    return 1;
}

sub needs_install_env ($self) {
    return ($self->{use_install_command} || $self->{_needs_install_command} || $self->_has_install_postamble) ? 1 : 0;
}

1;
