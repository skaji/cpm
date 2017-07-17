use strict;
use warnings;
use utf8;
use Test::More;
use lib "xt/lib";
use CLI;
use File::pushd 'tempd';
use Path::Tiny;
use version;

plan skip_all => 'only for perl 5.16+' if $] < 5.016;

subtest test1 => sub {
    plan skip_all => 'only for perl 5.22+' if $] < 5.022;
    my $guard = tempd;
    path("cpanfile")->spew(qq{requires "Module::Build";\n});
    my $r = cpm_install "--target-perl", "5.10.1";
    like $r->err, qr/WARN Module::Build used to be core/;
    is $r->exit, 0;
    note $r->err;
};

subtest test2 => sub {
    my $guard = tempd;
    path("cpanfile")->spew(qq{requires 'HTTP::Tinyish';\n});
    my $r = cpm_install "--target-perl", "5.8.5";
    is $r->exit, 0;
    like $r->err, qr/DONE install parent-/;
    note $r->err;
};

subtest test3 => sub {
    my $guard = tempd;
    path("cpanfile")->spew(qq{requires 'HTTP::Tinyish';\n});
    my $r = cpm_install "--target-perl", "5.10.1";
    is $r->exit, 0;
    unlike $r->err, qr/DONE install parent-/;
    note $r->err;
};

done_testing;
