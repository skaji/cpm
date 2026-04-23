package App::cpm::Builder::Base;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use Config;
use File::Find ();
use File::Spec;

my sub nonempty ($path) {
    return if !-d $path;
    my $found;
    File::Find::find({
        wanted => sub (@) {
            return if !-f $File::Find::name;
            return if $File::Find::name =~ /\.exists$/;
            $found = 1;
            $File::Find::prune = 1;
        },
        no_chdir => 1,
    }, $path);
    return $found;
}

sub new ($class, %args) {
    bless \%args, $class;
}

sub meta ($self) {
    $self->{meta};
}

sub local_lib ($self) {
    $self->{local_lib};
}

sub _prepare_paths_cache ($self) {
    $self->{libs} = [
        grep { nonempty($_) }
        map { File::Spec->catdir($self->{directory}, qw(blib), $_) } qw(arch lib)
    ];
    $self->{paths} = [
        grep { nonempty($_) }
        map { File::Spec->catdir($self->{directory}, qw(blib), $_) } qw(script bin)
    ];
    return 1;
}

sub libs ($self) {
    $self->{libs};
}

sub paths ($self) {
    $self->{paths};
}

sub _local_lib_env_path ($self) {
    join $Config{path_sep}, File::Spec->catdir($self->local_lib, "bin"), ( $ENV{PATH} ? $ENV{PATH} : () );
}

sub _local_lib_env_perl5lib ($self) {
    join $Config{path_sep}, File::Spec->catdir($self->local_lib, "lib", "perl5"), ( $ENV{PERL5LIB} ? $ENV{PERL5LIB} : ());
}

sub _set_local_lib_env ($self) {
    return if !$self->local_lib;
    $ENV{PATH} = $self->_local_lib_env_path;
    $ENV{PERL5LIB} = $self->_local_lib_env_perl5lib;
}

sub _use_unsafe_inc ($self, $ctx) {
    if (exists $ENV{PERL_USE_UNSAFE_INC}) {
        return $ENV{PERL_USE_UNSAFE_INC};
    }
    if (exists $self->meta->{x_use_unsafe_inc}) {
        $ctx->log("Distribution opts in x_use_unsafe_inc: $self->{meta}{x_use_unsafe_inc}"); # XXX
        return $self->meta->{x_use_unsafe_inc};
    }
    1;
}

sub run_configure ($self, $ctx, $cmd) {
    local %ENV = %ENV;
    $ENV{PERL5_CPAN_IS_RUNNING} = $$;
    $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;
    $ENV{PERL5_CPANM_IS_RUNNING} = $$;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $self->_set_local_lib_env;
    $ctx->run_command($cmd, $self->{configure_timeout});
}

sub run_build ($self, $ctx, $cmd) {
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $self->_set_local_lib_env;
    $ctx->run_command($cmd, $self->{build_timeout});
}

sub run_test ($self, $ctx, $cmd) {
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $ENV{NONINTERACTIVE_TESTING} = 1;
    $self->_set_local_lib_env;
    $ctx->run_command($cmd, $self->{test_timeout});
}

sub run_install ($self, $ctx, $cmd) {
    local %ENV = %ENV;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $self->_set_local_lib_env;
    $ctx->run_command($cmd, 0);
}

1;
