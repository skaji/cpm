use strict;
use warnings;
use Test::More;
use lib ".";
use xt::CLI;
use Path::Tiny;

subtest ng => sub {
    my $cpanfile = Path::Tiny->tempfile;
    $cpanfile->spew(<<___);
requires "perl", "5.99.0";
requires 'Plack';
___
    my $r = cpm_install "--cpanfile", $cpanfile->stringify;
    isnt $r->exit, 0;
    unlike $r->err, qr/Plack/; # do not install Plack
};

subtest ng => sub {
    plan skip_all => 'only for perl 5.16+' if $] < 5.016;
    my $r = cpm_install "--target-perl", "5.8.0", "HTTP::Tinyish";
    isnt $r->exit, 0;
    like $r->err, qr/DONE install HTTP-Tiny-/; # install HTTP::Tiny anyway
    unlike $r->err, qr/DONE install HTTP-Tinyish-/;
    note $r->err;
};

done_testing;
