requires 'perl', '5.008005';

requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta';
requires 'CPAN::Meta::YAML';
requires 'Carton::Snapshot';
requires 'File::pushd';
requires 'HTTP::Tiny';
requires 'IO::Socket::SSL';
requires 'JSON::PP';
requires 'Module::CPANfile';
requires 'Module::CoreList';
requires 'Module::Metadata';
requires 'local::lib';
requires 'version';

# for a while, you have to manually install this:
# $ cpanm git://github.com/miyagawa/cpanminus.git@menlo
requires 'Menlo::CLI::Compat', git => 'git://github.com/miyagawa/cpanminus.git', ref => 'menlo';

on test => sub {
    requires 'Test::More', '0.96';
};
