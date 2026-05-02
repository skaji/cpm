my @prereq = (
    [ Prereqs => 'ConfigureRequires' ] => [
        'Module::Build::Tiny' => '0.051',
        'perl' => 'v5.24',
    ],
    [ Prereqs => 'DevelopRequires' ] => [
        'Archive::Tar' => '0',
        'Archive::Zip' => '1.68',
        'CPAN::Mirror::Tiny' => '0.20',
        'Capture::Tiny' => '0',
        'Path::Tiny' => '0',
        'local::lib' => '0',
    ],
    [ Prereqs => 'RuntimeRecommends' ] => [
        'Carton' => '0',
    ],
    [ Prereqs => 'RuntimeRequires' ] => [
        'CPAN::02Packages::Search' => '0.100',
        'CPAN::DistnameInfo' => '0',
        'Command::Runner' => '0.201',
        'Darwin::InitObjC' => '0',
        'ExtUtils::Config' => '0',
        'ExtUtils::Helpers' => '0',
        'ExtUtils::Install' => '2.20',
        'ExtUtils::InstallPaths' => '0.002',
        'File::Copy::Recursive' => '0',
        'File::Which' => '0',
        'File::pushd' => '0',
        'HTTP::Tinyish' => '0.12',
        'IPC::Run3' => '0',
        'Module::CPANfile' => '0',
        'Module::cpmfile' => '0.001',
        'Parallel::Pipes::App' => '0.201',
        'Parse::LocalDistribution' => '0.20',
        'Proc::ForkSafe' => '0.001',
        'perl' => 'v5.24',
    ],
);

my @plugin = (
    'ExecDir' => [ dir => 'script' ],
    'Git::GatherDir' => [ exclude_filename => 'META.json' ],
    'CopyFilesFromBuild' => [ copy => 'META.json' ],
    'VersionFromMainModule' => [],
    'ReversionOnRelease' => [ prompt => 1 ],
    'NextRelease' => [ format => '%v  %{yyyy-MM-dd HH:mm:ss VVV}d%{ (TRIAL RELEASE)}T' ],
    'lib' => [ lib => 'author' ],
    '=Trial' => [],
    'Git::Check' => [ allow_dirty => 'Changes', allow_dirty => 'META.json' ],
    'Run::BeforeRelease' => [
        run => 'git fetch origin',
        run => q{%x -e 'my $behind = qx(git rev-list --count HEAD..\@{u}); chomp $behind; die "local branch is behind upstream by $behind commit(s); pull/rebase before release\n" if $behind'},
    ],
    'GithubMeta' => [ issues => 1 ],
    'MetaProvides::Package' => [ inherit_version => 0, inherit_missing => 0 ],
    'PruneFiles' => [ filename => 'AGENTS.md', filename => 'dist.pl', filename => 'cpm', filename => 'README.md', match => '^(xt|author|maint|example|eg)/' ],
    'GenerateFile' => [ filename => 'Build.PL', content => "use Module::Build::Tiny;\nBuild_PL();" ],
    'MetaJSON' => [],
    'Metadata' => [ x_static_install => 1 ],
    'Git::Contributors' => [],

    'CheckChangesHasContent' => [],
    'ConfirmRelease' => [],
    'UploadToCPAN' => [],
    'CopyFilesFromRelease' => [ match => '\.pm$' ],

    # XXX
    'Run::AfterRelease' => [ run => 'env CPAN_RELEASE_VERSION=%v%t %x author/fatpack.pl' ],

    'Git::Commit' => [ commit_msg => '%v%t', allow_dirty => 'Changes', allow_dirty => 'META.json', allow_dirty => 'cpm', allow_dirty_match => '\.pm$' ],
    'Git::Tag' => [ tag_format => '%v%t', tag_message => '%v%t' ],
    'Git::Push' => [],

    # XXX
    'Run::AfterBuild' => [ run_if_release => 'rm -rf author/local', run_if_release => '%x author/fatpack.pl --update-only' ],
);

my @config = (
    name => 'App-cpm',
    [ @prereq, @plugin ],
);
