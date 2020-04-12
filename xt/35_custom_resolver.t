use strict;
use warnings;
use Test::More;

use lib "xt/lib";
use CLI;

use File::Temp 'tempdir';
use Path::Tiny 'path';

plan skip_all => 'only for perl 5.16+' if $] < 5.016;

my $tempdir = tempdir CLEANUP => 1;
path($tempdir, qw(lib App cpm Resolver))->mkpath;
path($tempdir, qw(lib App cpm Resolver Hoge.pm))->spew_raw(<<'EOF');
package App::cpm::Resolver::Hoge;
sub new {
    bless {}, shift;
}
sub resolve {
    my ($self, $job) = @_;
    if ($job->{package} ne 'App::ChangeShebang') {
        die;
    }
    return +{
        uri => 'https://github.com/skaji/change-shebang/archive/master.tar.gz',
    };
}
1;
EOF

path($tempdir, qw(lib Foo))->mkpath;
path($tempdir, qw(lib Foo Bar.pm))->spew_raw(<<'EOF');
package Foo::Bar;
sub new {
    my ($class, @argv) = @_;
    die if !(@argv == 2 && $argv[0] eq "arg1" && $argv[1] eq "arg2");
    bless {}, shift;
}
sub resolve {
    my ($self, $job) = @_;
    if ($job->{package} ne 'App::ChangeShebang') {
        die;
    }
    return +{
        uri => 'https://github.com/skaji/change-shebang/archive/master.tar.gz',
    };
}
1;
EOF

my $r = do {
    local %ENV = %ENV;
    $ENV{PERL5LIB} = $ENV{PERL5LIB} ? "$ENV{PERL5LIB}:$tempdir/lib" : "$tempdir/lib";
    cpm_install "-r", "Hoge", "App::ChangeShebang";
};

is $r->exit, 0;
like $r->log, qr/Resolved App::ChangeShebang.*from Hoge/;

$r = do {
    local %ENV = %ENV;
    $ENV{PERL5LIB} = $ENV{PERL5LIB} ? "$ENV{PERL5LIB}:$tempdir/lib" : "$tempdir/lib";
    cpm_install "-r", "+Foo::Bar,arg1,arg2", "App::ChangeShebang";
};

is $r->exit, 0;
like $r->log, qr/Resolved App::ChangeShebang.*from Foo::Bar/;

done_testing;
