requires 'perl', '5.008001';

requires 'CPAN::Common::Index';
requires 'CPAN::DistnameInfo';
requires 'CPAN::Meta';
requires 'CPAN::Meta::Requirements', '2.130'; # for v-strings
requires 'CPAN::Meta::YAML';
requires 'Capture::Tiny';
requires 'Class::Tiny';
requires 'Command::Runner', '0.002';
requires 'ExtUtils::InstallPaths', '0.002';
requires 'File::Copy::Recursive';
requires 'File::pushd';
requires 'HTTP::Tiny', '0.055';
requires 'HTTP::Tinyish', '0.12';
requires 'JSON::PP', '2.27300'; # for perl 5.8.6 or below
requires 'Menlo', '1.9011';
requires 'Module::CPANfile';
requires 'Module::Metadata';
requires 'Parallel::Pipes', '0.004';
requires 'local::lib', '2.000018';
requires 'parent';
requires 'version', '0.77';

recommends 'IO::Uncompress::Gunzip';
recommends 'Carton';

on develop => sub {
    requires 'CPAN::Mirror::Tiny', '0.20';
    requires 'Capture::Tiny';
    requires 'Path::Tiny';
    requires 'Test::More', '0.98';
};
