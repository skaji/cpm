use strict;
use warnings;
use Test::More;

use App::cpm::Util 'WIN32';
use File::Temp ();

plan skip_all => 'non win32 test' if WIN32;

my $tempdir = File::Temp->newdir;

my $exit = do {
    local %ENV = %ENV;
    $ENV{_TEST_PERL} = $^X;
    $ENV{_TEST_DIR} = "". $tempdir;
    system "bash", "xt/37_global_local_lib/main.sh";
};

is $exit, 0;

done_testing;
