use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use Test::More;
use lib "xt/lib";
use CLI;

subtest argv => sub () {
    # ExtUtils::MakeMaker depends on Encode
    # https://metacpan.org/release/BINGOS/ExtUtils-MakeMaker-7.78/source/META.json#L39
    #
    # Encode depends on ExtUtils::MakeMaker
    # https://metacpan.org/release/DANKOGAI/Encode-3.24/source/META.json#L30
    my $res = cpm_install 'ExtUtils::MakeMaker', 'Encode';
    is $res->exit, 0 or diag $res->log;
};

done_testing;
