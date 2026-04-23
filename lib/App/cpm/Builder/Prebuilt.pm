package App::cpm::Builder::Prebuilt;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Builder::Base';

use Config;
use ExtUtils::Install ();
use ExtUtils::InstallPaths ();
use File::Spec;

sub new ($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->_prepare_paths_cache;
    return $self;
}

sub test ($self, $ctx) {
    die ref($self) . " does not implement test";
}

sub install ($self, $ctx, $dependency_libs, $dependency_paths) {
    my $install_base = $self->{install_base};

    $self->run_install($ctx, sub {
        $ctx->log("Copying prebuilt blib");
        my $paths = ExtUtils::InstallPaths->new(
            dist_name => $self->meta->name,
            $install_base ? (install_base => $install_base) : (),
        );
        my $install_base_meta = $install_base ? File::Spec->catdir($install_base, "lib", "perl5") : $Config{sitelibexp};
        my $meta_target_dir = File::Spec->catdir($install_base_meta, $Config{archname}, ".meta", $self->{distvname});

        open my $fh, ">", \my $stdout;
        {
            local *STDOUT = $fh;
            ExtUtils::Install::install([
                from_to => $paths->install_map,
                verbose => 0,
                dry_run => 0,
                uninstall_shadows => 0,
                skip => undef,
                always_copy => 1,
                result => \my %result,
            ]);
            ExtUtils::Install::install({
                'blib/meta' => $meta_target_dir,
            });
        }
        $ctx->log($stdout);
        return 1;
    }, $dependency_libs, $dependency_paths);
}

1;
