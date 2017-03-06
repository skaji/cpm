requires 'perl', '5.008001';

requires 'CPAN::Common::Index::Mirror';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Requirements', '2.130'; # for v-strings
requires 'CPAN::Meta::YAML';
requires 'Capture::Tiny';
requires 'Class::Tiny';
requires 'File::Copy::Recursive';
requires 'File::pushd';
requires 'HTTP::Tiny', '0.055';
requires 'HTTP::Tinyish', '0.12';
requires 'IO::Uncompress::Gunzip';
requires 'JSON::PP', '2.27300'; # for perl 5.8.6 or below
requires 'Menlo::CLI::Compat';
requires 'Module::CPANfile';
requires 'Module::Metadata';
requires 'Parallel::Pipes';
requires 'Pod::Usage', '1.33'; # for perl 5.8.6 or below
requires 'local::lib', '2.000018';
requires 'parent';
requires 'version', '0.77';

recommends 'Carton::Snapshot';

on develop => sub {
    requires 'Capture::Tiny';
    requires 'Path::Tiny';
    requires 'CPAN::Mirror::Tiny', '0.10';
    requires 'Test::More', '0.98';
};
