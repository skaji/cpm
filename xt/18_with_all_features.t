use strict;
use warnings;
use utf8;
use Test::More;
use xt::CLI;
use xt::Dist;
use Path::Tiny;

my $dist = dist(
    name => 'has-features',
    prereqs => {
        runtime => {requires => {'Module::Build' => 0}},
    },
    optional_features => {
        'my-feature' => {
            prereqs => {
                runtime => {requires => {'HTTP::Tinyish' => 0}},
            },
        },
    },
);

subtest default => sub {
    my $r = cpm_install $dist;
    unlike $r->err, qr/^DONE install HTTP-Tinyish/m or diag $r->err;
};

subtest with_all_features => sub {
    my $r = cpm_install $dist, '--with-all-features';
    like $r->err, qr/^DONE install HTTP-Tinyish/m or diag $r->err;
};

done_testing;
