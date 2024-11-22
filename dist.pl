my @prereq = (
    [ Prereqs => 'ConfigureRequires' ] => [
        'Module::Build::Tiny' => '0.051',
        'perl' => '5.008001',
    ],
    [ Prereqs => 'DevelopRequires' ] => [
        'Archive::Tar' => '0',
        'Archive::Zip' => '1.68',
        'CPAN::Mirror::Tiny' => '0.20',
        'Capture::Tiny' => '0',
        'Path::Tiny' => '0',
        'Test::More' => '0.98',
    ],
    [ Prereqs => 'RuntimeRecommends' ] => [
        'Carton' => '0',
    ],
    [ Prereqs => 'RuntimeRequires' ] => [
        'CPAN::02Packages::Search' => '0.100',
        'CPAN::DistnameInfo' => '0',
        'CPAN::Meta' => '0',
        'CPAN::Meta::Requirements' => '2.130',
        'CPAN::Meta::YAML' => '0',
        'Command::Runner' => '0.100',
        'ExtUtils::Install' => '2.20',
        'ExtUtils::InstallPaths' => '0.002',
        'File::Copy::Recursive' => '0',
        'File::pushd' => '0',
        'HTTP::Tinyish' => '0.12',
        'JSON::PP' => '2.27300',
        'Menlo::CLI::Compat' => '1.9021',
        'Module::CPANfile' => '0',
        'Module::Metadata' => '0',
        'Module::cpmfile' => '0.001',
        'Parallel::Pipes::App' => '0.100',
        'Parse::PMFile' => '0.43',
        'Proc::ForkSafe' => '0.001',
        'local::lib' => '2.000018',
        'parent' => '0',
        'perl' => '5.008001',
        'version' => '0.77',
    ],
);

my @config = (
    name => 'App-cpm',

    [
        @prereq,
        'ExecDir' => [ dir => 'script' ],
        'Git::GatherDir' => [ exclude_filename => 'META.json', exclude_filename => 'LICENSE' ],
        'CopyFilesFromBuild' => [ copy => 'META.json', copy => 'LICENSE' ],
        'VersionFromMainModule' => [],
        'LicenseFromModule' => [ override_author => 1 ],
        'ReversionOnRelease' => [ prompt => 1 ],
        'NextRelease' => [ format => '%v  %{yyyy-MM-dd HH:mm:ss VVV}d%{ (TRIAL RELEASE)}T' ],
        'Git::Check' => [ allow_dirty => 'Changes', allow_dirty => 'META.json' ],
        'GithubMeta' => [ issues => 1 ],
        'MetaProvides::Package' => [ inherit_version => 0, inherit_missing => 0 ],
        'PruneFiles' => [ filename => 'dist.pl', filename => 'cpm', filename => 'README.md', match => '^(xt|author|maint|example|eg)/' ],
        'GenerateFile' => [ filename => 'Build.PL', content => "use Module::Build::Tiny;\nBuild_PL();" ],
        'MetaJSON' => [],
        'Metadata' => [ x_static_install => 1 ],
        'Git::Contributors' => [],
        'License' => [],

        'CheckChangesHasContent' => [],
        'ConfirmRelease' => [],
        'UploadToCPAN' => [],
        'CopyFilesFromRelease' => [ match => '\.pm$' ],

        # XXX
        'Run::AfterRelease' => [ run => 'env CPAN_RELEASE_VERSION=%v %x author/fatpack.pl' ],

        'Git::Commit' => [ commit_msg => '%v', allow_dirty => 'Changes', allow_dirty => 'META.json', allow_dirty => 'cpm', allow_dirty_match => '\.pm$' ],
        'Git::Tag' => [ tag_format => '%v', tag_message => '%v' ],
        'Git::Push' => [],

        # XXX
        'Run::AfterBuild' => [ run_if_release => 'rm -rf author/local', run_if_release => '%x author/fatpack.pl --update-only' ],
    ],
);
