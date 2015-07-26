requires 'perl', '5.008005';

requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Requirements';
requires 'CPAN::Meta::YAML';
requires 'Carton::Snapshot';
requires 'File::pushd';
requires 'HTTP::Tiny';
requires 'JSON::PP';
requires 'Module::CPANfile';
requires 'Module::CoreList';
requires 'Module::Metadata';
requires 'local::lib';
requires 'version';

# for a while, you have to manually install this:
# $ cpanm git://github.com/miyagawa/cpanminus.git@menlo
requires 'Menlo::CLI::Compat', git => 'git://github.com/miyagawa/cpanminus.git', ref => 'menlo';

# cf: https://github.com/miyagawa/cpanminus/blob/devel/lib/App/cpanminus/script.pm
requires 'Module::Build', '0.38';       # shipt with  perl v5.13.11
requires 'ExtUtils::MakeMaker', '6.58'; # shipt with  perl v5.15.1
requires 'ExtUtils::Install', '1.46';   # shipt after perl v5.10.1

on test => sub {
    requires 'Test::More', '0.96';
};
