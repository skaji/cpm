use v5.42;

package Trial {
    use Moose;
    with 'Dist::Zilla::Role::FileMunger';
    sub munge_file ($self, $file) {
        return if !($ENV{DZIL_RELEASING} && $file->name eq $self->zilla->main_module->name);
        my @line;
        for my $line (split /\n/, $file->content, -1) {
            if ($line =~ /^our \$TRIAL/) {
                my $trial_line = sprintf 'our $TRIAL = %d;', $self->zilla->is_trial ? 1 : 0;
                push @line, $trial_line;
            } else {
                push @line, $line;
            }
        }
        $file->content(join "\n", @line);
    }
}

package VersionFromMainModule {
    use Moose;
    with 'Dist::Zilla::Role::VersionProvider', 'Dist::Zilla::Role::ModuleMetadata';
    sub provide_version ($self, @) {
        my $metadata = $self->module_metadata_for_file($self->zilla->main_module, collect_pod => 0);
        my $version = $metadata->version;
        "$version";
    }
}

package NextRelease {
    use Moose;
    extends 'Dist::Zilla::Plugin::NextRelease';
    sub after_release ($self, @) {} # noop
}

my @prereq = (
    [ Prereqs => 'ConfigureRequires' ] => [
        'Module::Build::Tiny' => '0.053',
    ],
    [ Prereqs => 'DevelopRequires' ] => [
        'Archive::Tar' => '0',
        'Archive::Zip' => '1.68',
        'CPAN::Mirror::Tiny' => 'v1.0.0',
        'Capture::Tiny' => '0',
        'Path::Tiny' => '0',
        'local::lib' => '0',
    ],
    [ Prereqs => 'RuntimeRecommends' ] => [
        'Carton' => '0',
    ],
    [ Prereqs => 'RuntimeRequires' ] => [
        'CPAN::02Packages::Search' => 'v1.0.0',
        'CPAN::DistnameInfo' => '0',
        'Command::Runner' => 'v1.0.0',
        'Darwin::InitObjC' => 'v1.0.0',
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
        'Module::cpmfile' => 'v1.0.0',
        'Parallel::Pipes::App' => 'v1.0.0',
        'Parse::LocalDistribution' => '0.20',
        'Proc::ForkSafe' => 'v1.0.0',
        'perl' => 'v5.24',
    ],
);

my @plugin = (
    'ExecDir' => [ dir => 'script' ],
    'Git::GatherDir' => [ exclude_filename => 'META.json' ],
    'CopyFilesFromBuild' => [ copy => 'META.json' ],
    '=VersionFromMainModule' => [],
    'ReversionOnRelease' => [],
    '=NextRelease' => [ format => '%v  %{yyyy-MM-dd HH:mm:ss VVV}d%{ (TRIAL RELEASE)}T' ],
    '=Trial' => [],
    'Git::Check' => [ allow_dirty => 'Changes', allow_dirty => 'META.json' ],
    'GithubMeta' => [ issues => 1 ],
    'MetaProvides::Package' => [ inherit_version => 0, inherit_missing => 0 ],
    'MetaJSON' => [],
    'Metadata' => [ x_static_install => 1 ],
    'Git::Contributors' => [],

    'CheckChangesHasContent' => [],
    'FakeRelease' => [],
    'CopyFilesFromRelease' => [ filename => 'Changes', match => '\.pm$', ],

    # XXX
    'Run::AfterRelease' => [ run => 'env CPAN_RELEASE_VERSION=%v%t %x author/fatpack.pl' ],

    'Git::Commit' => [ commit_msg => '%v%t', allow_dirty => 'Changes', allow_dirty => 'META.json', allow_dirty_match => '\.pm$', allow_dirty => 'cpm' ],
    'Git::Tag' => [ tag_format => '%v%t', tag_message => '%v%t' ],
    'Git::Push' => [],

    # XXX
    'Run::AfterBuild' => [ run_if_release => 'rm -rf author/local', run_if_release => '%x author/fatpack.pl --update-only' ],
);

my @config = (
    name => 'App-cpm',
    [ @prereq, @plugin ],
);
