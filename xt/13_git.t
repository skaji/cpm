use strict;
use warnings;
use Test::More;
use xt::CLI;

subtest git1 => sub {
    my $r = cpm_install "-v", "https://github.com/skaji/change-shebang.git";
    is $r->exit, 0;
    note $r->err;
};

subtest git2 => sub {
    my $r = cpm_install "-v", 'https://github.com/skaji/change-shebang.git@0.05', "App::FatPacker";
    is $r->exit, 0;
    note $r->err;
};

done_testing;
