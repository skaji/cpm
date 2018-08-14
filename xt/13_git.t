use strict;
use warnings;
use Test::More;
use lib "xt/lib";
use CLI;

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

subtest git_subdir => sub {
    my $r = cpm_install 'https://github.com/miyagawa/cpanminus.git/Menlo@1.9019';
    is $r->exit, 0;
    like $r->err, qr{DONE install Menlo-1.9019 \(https://github.com/miyagawa/cpanminus.git/Menlo\@74d7997c2b35b1bfb964530e2675773ca54b581e\)};
    note $r->err;
};

subtest git_describe => sub {
    my $r = cpm_install 'https://github.com/skaji/change-shebang.git@6eadaaa';
    is $r->exit, 0;
    like $r->err, qr{DONE install App-ChangeShebang-0.05_02 \(https://github.com/skaji/change-shebang.git\@6eadaaaadf79ea9a90b1a4d995af794b9133d634\)};
    note $r->err;
};

subtest git_notags => sub {
    my $r = cpm_install 'https://github.com/skaji/change-shebang.git@92651ea';
    is $r->exit, 0;
    like $r->err, qr{DONE install App-ChangeShebang-0.000_351143984 \(https://github.com/skaji/change-shebang.git\@92651ea73c26191f0c6934dcfed1e4e5f181b1b4\)};
    note $r->err;
};

subtest git_nometa => sub {
    my $r = cpm_install 'https://github.com/my-mail-ru/perl-AnyEvent-HTTP-ProxyChain.git@1.02';
    is $r->exit, 0;
    like $r->err, qr{DONE install AnyEvent-HTTP-ProxyChain-1.02 \(https://github.com/my-mail-ru/perl-AnyEvent-HTTP-ProxyChain.git\@b584eb9747a061a525044fd95ed42cf64ec7826c\)};
    note $r->err;
};

subtest git_libonly => sub {
    my $r = cpm_install 'https://github.com/my-mail-ru/perl-MR-Rest.git@2119a95';
    is $r->exit, 0;
    like $r->err, qr{DONE install MR-Rest-0.000_353848525 \(https://github.com/my-mail-ru/perl-MR-Rest.git\@2119a95aefe609113b0adcfc006569b2da109870\)};
    note $r->err;
};

subtest fail => sub {
    my $r = cpm_install "-v", "git://github.com/skaji/xxxxx.git";
    isnt $r->exit, 0;
    note $r->err;
    $r = cpm_install "-v", 'git://github.com/skaji/change-shebang.git@xxxxxx';
    isnt $r->exit, 0;
    note $r->err;
};

done_testing;
