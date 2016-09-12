use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;
use xt::Dist;
use Path::Tiny;

my $dist = dist(
    name    => 'develop-requires',
    prereqs => {
        runtime => {
            requires => {'Module::Build' => 0},
        },
        develop => {
            requires => {'HTTP::Tinyish' => 0},
        },
    },
);

subtest default => sub {
    my $r = cpm_install $dist;
    unlike $r->err, qr/^DONE install HTTP-Tinyish/m or diag $r->err;
};

subtest with_develop => sub {
    my $r = cpm_install $dist, '--with-develop';
    like $r->err, qr/^DONE install HTTP-Tinyish/m or diag $r->err;
};

done_testing;
