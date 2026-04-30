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

done_testing;
