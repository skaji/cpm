package App::cpm::Builder::Base;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use CPAN::DistnameInfo;
use Config;
use App::cpm::Util qw(DEBUG);
use ExtUtils::Install ();
use ExtUtils::InstallPaths ();
use File::Copy ();
use File::Find ();
use File::Path ();
use File::Spec;
use JSON::PP ();

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

sub _env_path ($self, $dependency_paths) {
    join $Config{path_sep},
        $dependency_paths->@*,
        ($self->local_lib ? File::Spec->catdir($self->local_lib, "bin") : ()),
        ( $ENV{PATH} ? $ENV{PATH} : () );
}

sub _env_perl5lib ($self, $dependency_libs) {
    join $Config{path_sep},
        $dependency_libs->@*,
        ($self->local_lib ? File::Spec->catdir($self->local_lib, "lib", "perl5") : ()),
        ( $ENV{PERL5LIB} ? $ENV{PERL5LIB} : ());
}

sub _set_env ($self, $dependency_libs, $dependency_paths) {
    if ($dependency_paths->@* || $self->local_lib) {
        $ENV{PATH} = $self->_env_path($dependency_paths);
    }

    if ($dependency_libs->@* || $self->local_lib) {
        $ENV{PERL5LIB} = $self->_env_perl5lib($dependency_libs);
    }
}

sub _write_blib_meta ($self, $ctx) {
    my $name = $self->meta->{name};
    $name =~ s/-/::/g;

    my %provides = map {
        my $package = $_->{package};
        my %info;
        $info{file} = $_->{file};
        $info{version} = $_->{version} if $_->{version};
        ($package, \%info);
    } $self->{provides}->@*;

    my %install = (
        name => $name,
        target => $name,
        version => $self->meta->{version},
        dist => $self->{distvname},
        pathname => $self->{distfile},
        provides => \%provides,
    );

    File::Path::mkpath("blib/meta", 0, 0777);
    {
        open my $fh, ">", "blib/meta/install.json" or die $!;
        print {$fh} JSON::PP->new->canonical->pretty->encode(\%install);
        close $fh;
    }

    File::Copy::copy("MYMETA.json", "blib/meta/MYMETA.json") or die $!;
    return 1;
}

sub _install_paths ($self) {
    ExtUtils::InstallPaths->new(
        dist_name => $self->meta->name,
        ($self->{install_base} ? (install_base => $self->{install_base}) : ()),
    );
}

sub _install_blib ($self, $ctx) {
    open my $fh, ">", \my $stdout;
    {
        local *STDOUT = $fh;
        ExtUtils::Install::install($self->_install_paths->install_map, 0, 0, 0);
    }
    $ctx->log($stdout);
    return 1;
}

sub _install_blib_meta ($self, $ctx) {
    my $install_base = $self->{install_base};
    my $install_base_meta = $install_base ? File::Spec->catdir($install_base, "lib", "perl5") : $Config{sitelibexp};
    my $meta_target_dir = File::Spec->catdir($install_base_meta, $Config{archname}, ".meta", $self->{distvname});

    open my $fh, ">", \my $stdout;
    {
        local *STDOUT = $fh;
        ExtUtils::Install::install({
            'blib/meta' => $meta_target_dir,
        });
    }
    $ctx->log($stdout);
    return 1;
}

sub install ($self, $ctx) {
    $self->_install_blib($ctx);
    $self->_install_blib_meta($ctx);
    return 1;
}

sub _log_env ($self, $ctx) {
    if (exists $ENV{PERL5LIB}) {
        $ctx->log("PERL5LIB: $_") for split /\Q$Config{path_sep}\E/, $ENV{PERL5LIB};
    }
    if (exists $ENV{PATH}) {
        $ctx->log("PATH: $_") for split /\Q$Config{path_sep}\E/, $ENV{PATH};
    }
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

sub run_configure ($self, $ctx, $cmd, $dependency_libs, $dependency_paths) {
    local %ENV = %ENV;
    $ENV{PERL5_CPAN_IS_RUNNING} = $$;
    $ENV{PERL5_CPANPLUS_IS_RUNNING} = $$;
    $ENV{PERL5_CPANM_IS_RUNNING} = $$;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $self->_set_env($dependency_libs, $dependency_paths);
    DEBUG and $self->_log_env($ctx);
    $ctx->run_command($cmd, $self->{configure_timeout});
}

sub run_build ($self, $ctx, $cmd, $dependency_libs, $dependency_paths) {
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $self->_set_env($dependency_libs, $dependency_paths);
    DEBUG and $self->_log_env($ctx);
    $ctx->run_command($cmd, $self->{build_timeout});
}

sub run_test ($self, $ctx, $cmd, $dependency_libs, $dependency_paths) {
    local %ENV = %ENV;
    $ENV{PERL_MM_USE_DEFAULT} = 1;
    $ENV{PERL_USE_UNSAFE_INC} = $self->_use_unsafe_inc($ctx);
    $ENV{NONINTERACTIVE_TESTING} = 1;
    $self->_set_env($dependency_libs, $dependency_paths);
    DEBUG and $self->_log_env($ctx);
    $ctx->run_command($cmd, $self->{test_timeout});
}

1;
