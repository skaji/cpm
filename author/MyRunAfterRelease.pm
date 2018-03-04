package MyRunAfterRelease;

use Moose;
extends 'Dist::Zilla::Plugin::Run::AfterRelease';

use Dist::Zilla::Plugin::Git::Commit;

sub _inject {
    my ($array, $sub, $item) = @_;
    my ($i) = grep { local $_ = $array->[$_]; $sub->($_) } 0.. $#{$array};
    if (defined $i) {
        splice @$array, $i + 1, 0, $item;
        return 1;
    }
    return;
}

sub _replace {
    my ($array, $sub, $item) = @_;
    my ($i) = grep { local $_ = $array->[$_]; $sub->($_) } 0.. $#{$array};
    if (defined $i) {
        splice @$array, $i, 1, $item;
        return 1;
    }
    return;
}

# https://metacpan.org/source/RJBS/Dist-Zilla-6.011/lib/Dist/Zilla/Role/Plugin.pm
around register_component => sub {
    my ($orig, $class, $name, $arg, $section) = @_;
    my $self = $class->plugin_from_config($name, $arg, $section);
    my $version = $self->VERSION || 0;
    $self->log_debug([ 'online, %s v%s', $self->meta->name, $version ]);

    _inject $self->zilla->plugins, sub { ref $_ eq "Dist::Zilla::Plugin::CopyFilesFromRelease" }, $self or die;

    my @dirty_files = ('dist.ini', 'Changes', 'META.json', 'README.md', "cpm");
    my $git_commit = Dist::Zilla::Plugin::Git::Commit->new({
        commit_msg => '%v',
        allow_dirty => \@dirty_files,
        allow_dirty_match => ['\.pm$'],
        plugin_name => "Dist::Zilla::Plugin::Git::Commit",
        zilla => $section->sequence->assembler->zilla,
    });
    _replace $self->zilla->plugins, sub { ref $_ eq "Dist::Zilla::Plugin::Git::Commit" }, $git_commit or die;
    return;
};

__PACKAGE__->meta->make_immutable;

1;
