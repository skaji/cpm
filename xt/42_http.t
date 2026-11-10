use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use Test::More;
use File::Temp ();
use lib "xt/lib";
use CLI;

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

subtest automatic_backend_order => sub () {
    my @attempted;
    local *HTTP::Tinyish::configure_backend = sub ($class, $backend) {
        push @attempted, $backend;
        return;
    };
    eval { App::cpm::HTTP->create };
    like $@, qr/Couldn't find HTTP Clients that support https/;
    is_deeply \@attempted, [qw(App::cpm::HTTP::_HTTPTiny HTTP::Tinyish::LWP HTTP::Tinyish::Curl HTTP::Tinyish::Wget)];
};

subtest explicit_backend_does_not_fallback => sub () {
    my @attempted;
    local *HTTP::Tinyish::configure_backend = sub ($class, $backend) {
        push @attempted, $backend;
        return;
    };
    eval { App::cpm::HTTP->create(prefer => ['Wget']) };
    like $@, qr/Couldn't find HTTP Clients that support https \(requested: Wget\)/;
    is_deeply \@attempted, ['HTTP::Tinyish::Wget'];
};

subtest explicit_backend_requires_https => sub () {
    local *HTTP::Tinyish::configure_backend = sub (@) { +{'HTTP::Tiny' => 'fixture'} };
    local *App::cpm::HTTP::_HTTPTiny::supports = sub (@) { 0 };
    eval { App::cpm::HTTP->create(prefer => ['HTTPTiny']) };
    like $@, qr/Couldn't find HTTP Clients that support https \(requested: HTTPTiny\)/;
};

subtest cli_selects_wget => sub () {
    my $backend = 'HTTP::Tinyish::Wget';
    my $meta = HTTP::Tinyish->configure_backend($backend);
    if (!$meta || !$backend->supports('https')) {
        plan skip_all => 'wget with HTTPS support is not available';
        return;
    }
    my ($fh, $cpanfile) = File::Temp::tempfile(UNLINK => 1);
    close $fh;
    my $result = cpm_install '--http-backend=wget', '--no-default-resolvers', '--cpanfile', $cpanfile;
    is $result->exit, 0;
    like $result->log, qr/You have .*wget/i;
};

done_testing;
