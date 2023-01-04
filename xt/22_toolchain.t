use strict;
use warnings;
use utf8;
use Test::More;
use lib "xt/lib";
use CLI;

subtest module_build => sub {
    my $r = cpm_install 'Module::Build@0.4232';
    is $r->exit, 0;
    like $r->err, qr/DONE install Module(?:-|::)Build/;
    note $r->err;
};
subtest eumm => sub {
    my $r = cpm_install 'ExtUtils::MakeMaker@7.22';
    is $r->exit, 0;
    like $r->err, qr/DONE install ExtUtils(?:-|::)MakeMaker/;
    note $r->err;
};
subtest eupxs => sub {
    my $r = cpm_install 'ExtUtils::ParseXS@3.24';
    is $r->exit, 0;
    like $r->err, qr/DONE install ExtUtils(?:-|::)ParseXS/;
    note $r->err;
};
subtest eui => sub {
    my $r = cpm_install 'ExtUtils::Install@2.02';
    is $r->exit, 0;
    like $r->err, qr/DONE install ExtUtils(?:-|::)Install/;
    note $r->err;
};

done_testing;
