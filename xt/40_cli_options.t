use v5.24;
use warnings;
use experimental qw(signatures);

use Test::More;
use App::cpm::CLI;

local $ENV{PERL_CPM_HTTP_BACKEND};

subtest use_install_command_disables_prebuilt => sub () {
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--use-install-command", "ModuleA");
    is $cli->{use_install_command}, 1;
    is $cli->{prebuilt}, 0;
};

subtest use_install_command_disables_explicit_prebuilt => sub () {
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--prebuilt", "--use-install-command", "ModuleA");
    is $cli->{use_install_command}, 1;
    is $cli->{prebuilt}, 0;
};

subtest no_use_install_command_keeps_prebuilt => sub () {
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--no-use-install-command", "ModuleA");
    is $cli->{use_install_command}, 0;
    is $cli->{prebuilt}, 1;
};

subtest report_perl_version_defaults_to_on => sub () {
    local @ENV{qw(CI AUTOMATED_TESTING AUTHOR_TESTING)};
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("ModuleA");
    is $cli->{report_perl_version}, 1;
};

subtest report_perl_version_defaults_to_off_on_ci => sub () {
    local $ENV{CI} = 1;
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("ModuleA");
    ok !$cli->{report_perl_version};
};

subtest no_report_perl_version_disables_reporting => sub () {
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--no-report-perl-version", "ModuleA");
    is $cli->{report_perl_version}, 0;
};

subtest report_perl_version_overrides_ci_default => sub () {
    local $ENV{CI} = 1;
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--report-perl-version", "ModuleA");
    is $cli->{report_perl_version}, 1;
};

subtest http_backend_defaults_to_auto => sub () {
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("ModuleA");
    ok !defined $cli->{http_backend};
};

subtest http_backend_names_are_case_insensitive => sub () {
    for my $case (
        ['httptiny', 'HTTPTiny'],
        ['HTTPTiny', 'HTTPTiny'],
        ['lwp', 'LWP'],
        ['curl', 'Curl'],
        ['WGET', 'Wget'],
        ['auto', undef],
    ) {
        my ($option, $expected) = @$case;
        my $cli = App::cpm::CLI->new;
        ok $cli->parse_options("--http-backend=$option", "ModuleA"), $option;
        is $cli->{http_backend}, $expected;
    }
};

subtest http_backend_environment_default => sub () {
    local $ENV{PERL_CPM_HTTP_BACKEND} = 'wget';
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("ModuleA");
    is $cli->{http_backend}, 'Wget';
};

subtest http_backend_option_overrides_environment => sub () {
    local $ENV{PERL_CPM_HTTP_BACKEND} = 'wget';
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--http-backend=curl", "ModuleA");
    is $cli->{http_backend}, 'Curl';
};

subtest http_backend_auto_overrides_environment => sub () {
    local $ENV{PERL_CPM_HTTP_BACKEND} = 'wget';
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--http-backend=auto", "ModuleA");
    ok !defined $cli->{http_backend};
};

subtest http_backend_option_overrides_invalid_environment => sub () {
    local $ENV{PERL_CPM_HTTP_BACKEND} = 'unknown';
    my $cli = App::cpm::CLI->new;
    ok $cli->parse_options("--http-backend=wget", "ModuleA");
    is $cli->{http_backend}, 'Wget';
};

subtest invalid_http_backend_is_rejected => sub () {
    my $cli = App::cpm::CLI->new;
    my $ok = eval { $cli->parse_options("--http-backend=unknown", "ModuleA"); 1 };
    ok !$ok;
    like $@, qr/Unknown HTTP backend 'unknown'.*auto, httptiny, lwp, curl, wget/;
};

subtest invalid_http_backend_environment_is_rejected => sub () {
    local $ENV{PERL_CPM_HTTP_BACKEND} = '';
    my $cli = App::cpm::CLI->new;
    my $ok = eval { $cli->parse_options("ModuleA"); 1 };
    ok !$ok;
    like $@, qr/Unknown HTTP backend ''/;
};

done_testing;
