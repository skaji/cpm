requires 'perl', '5.008005';

requires 'CPAN::Common::Index::Mirror';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Requirements', '2.130'; # for v-strings
requires 'CPAN::Meta::YAML';
requires 'Capture::Tiny';
requires 'Class::Tiny';
requires 'File::Copy::Recursive';
requires 'File::pushd';
requires 'HTTP::Tiny';
requires 'HTTP::Tinyish';
requires 'IO::Uncompress::Gunzip';
requires 'JSON::PP', '2.27300'; # for perl 5.8.6 or below
requires 'Module::CPANfile';
requires 'Module::CoreList';
requires 'Module::Metadata';
requires 'Parallel::Pipes';
requires 'Pod::Usage', '1.33'; # for perl 5.8.6 or below
requires 'local::lib', '2.000018';
requires 'parent';
requires 'version', '0.77';

requires 'Menlo::CLI::Compat';

# cf: https://github.com/miyagawa/cpanminus/blob/devel/lib/App/cpanminus/script.pm
requires 'Module::Build', '0.38';       # shipt with  perl v5.13.11
requires 'ExtUtils::MakeMaker', '6.58'; # shipt with  perl v5.15.1
requires 'ExtUtils::Install', '1.46';   # shipt after perl v5.10.1

recommends 'Carton::Snapshot';

on develop => sub {
    requires 'Capture::Tiny';
    requires 'Path::Tiny';
    requires 'CPAN::Mirror::Tiny', '0.10';
    requires 'Test::More', '0.98';
};
