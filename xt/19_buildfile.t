use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;
use Path::Tiny;
use File::pushd 'tempd';

subtest build_pl => sub {
    my $guard = tempd;
    with_same_local {
        cpm_install 'Module::Build';

        Path::Tiny->new("Build.PL")->spew(<<'EOF');
use Module::Build;
my $builder = Module::Build->new(
    module_name => 'TEST_MODULE',
    dist_version => '0.1',
    dist_author => 'skaji',
    dist_abstract => 'test',
    no_index => {},
    requires => { 'File::pushd' => 0 },
);
$builder->create_build_script;
EOF
        my $r = cpm_install;
        like $r->err, qr/Executing Build.PL/;
        like $r->err, qr/DONE install File-pushd-/;
    };
};

subtest makefile_pl => sub {
    my $guard = tempd;
    Path::Tiny->new("Makefile.PL")->spew(<<'EOF');
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME => 'TEST_MODULE',
    PREREQ_PM => { 'File::pushd' => 0 },
);
EOF
    my $r = cpm_install;
    like $r->err, qr/Executing Makefile.PL/;
    like $r->err, qr/DONE install File-pushd-/;
};

done_testing;
