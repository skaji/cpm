use v5.24;
use warnings;
use experimental qw(signatures);

use Test::More;
use App::cpm::CLI;

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

done_testing;
