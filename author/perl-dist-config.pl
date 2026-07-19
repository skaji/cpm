use v5.44;

my sub run (@cmd) { warn "---> @cmd\n"; !system @cmd or die }

my sub before_release ($data) {
    run "rm", "-rf", "author/local";
    run $^X, "author/fatpack.pl", "--update-only";
    run "git", "diff", "--quiet", "--exit-code";
    run "rm", "-rf", "author/local";
    {
        local $ENV{CPAN_RELEASE_VERSION} = $data->{version} . ($data->{trial} ? "-TRIAL" : "");
        run $^X, "author/fatpack.pl";
    }
    run "git", "add", "cpm";
}

my $config = {
    before_release => \&before_release,
};
