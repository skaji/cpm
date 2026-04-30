use v5.24;
use warnings;
use experimental qw(signatures);

use File::Path qw(mkpath);
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use App::cpm::Builder::Base;

subtest absent_local_lib_does_not_set_env => sub () {
    my $local = File::Spec->catdir(tempdir(CLEANUP => 1), "local");
    my $builder = App::cpm::Builder::Base->new(distfile => "A-1.0.tar.gz", local_lib => $local);

    local %ENV = ();
    $builder->_set_env([], []);

    ok !exists $ENV{PERL5LIB};
    ok !exists $ENV{PATH};
};

subtest existing_local_lib_paths_are_added => sub () {
    my $local = File::Spec->catdir(tempdir(CLEANUP => 1), "local");
    my $bin = File::Spec->catdir($local, "bin");
    my $lib = File::Spec->catdir($local, "lib", "perl5");
    mkpath [$bin, $lib];

    my $builder = App::cpm::Builder::Base->new(
        distfile => "A-1.0.tar.gz",
        local_lib => $local,
        local_bin => $bin,
        local_perl5lib => $lib,
    );

    local %ENV = ();
    $builder->_set_env([], []);

    is $ENV{PERL5LIB}, $lib;
    is $ENV{PATH}, $bin;
};

subtest dependency_paths_are_still_added_without_local_lib => sub () {
    my $local = File::Spec->catdir(tempdir(CLEANUP => 1), "local");
    my $builder = App::cpm::Builder::Base->new(distfile => "A-1.0.tar.gz", local_lib => $local);

    local %ENV = ();
    $builder->_set_env(["blib/lib"], ["blib/script"]);

    is $ENV{PERL5LIB}, "blib/lib";
    is $ENV{PATH}, "blib/script";
};

done_testing;
