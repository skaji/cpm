my @config = (
    name => 'App-cpm',

    [
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
        'PruneFiles' => [ filename => 'dist.pl', filename => 'cpm.yml', filename => 'cpm', filename => 'README.md', match => '^(xt|author|maint|example|eg)/' ],
        'Prereqs::From::cpmfile' => [],
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
