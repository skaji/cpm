use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use Test::More;

use App::cpm;
use App::cpm::HTTP;

subtest report_perl_version => sub () {
    my $http = App::cpm::HTTP->create(report_perl_version => 1);
    is($http->{agent} || $http->{_new_argv}{agent}, "App::cpm/$App::cpm::VERSION perl/$]", "reports Perl version in User-Agent");
};

subtest no_report_perl_version => sub () {
    my $http = App::cpm::HTTP->create(report_perl_version => 0);
    is($http->{agent} || $http->{_new_argv}{agent}, "App::cpm/$App::cpm::VERSION", "can omit Perl version from User-Agent");
};

done_testing;
