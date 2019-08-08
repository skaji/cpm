#!/usr/bin/env perl
use 5.28.0;
use FindBin;
use lib "$FindBin::Bin/../lib";
use App::FatPacker::Simple;
use App::cpm::CLI;
use Config;
use File::Path 'remove_tree';
use Carton::Snapshot;
use CPAN::Meta::Requirements;
use Getopt::Long ();
use Path::Tiny ();
chdir $FindBin::Bin;

=for hint

Show new dependencies

    git diff cpm | perl -nle 'print $1 if /^\+\$fatpacked\{"([^"]+)/'

=cut

Getopt::Long::GetOptions
    "f|force" => \my $force,
    "t|test" => \my $test,
    "update-only" => \my $update_only,
or exit 1;

sub cpm {
    App::cpm::CLI->new->run(@_) == 0 or die
}

sub fatpack {
    App::FatPacker::Simple->new->parse_options(@_)->run
}

sub remove_version_xs {
    my $arch = $Config{archname};
    my $file = "local/lib/perl5/$arch/version/vxs.pm";
    my $dir  = "local/lib/perl5/$arch/auto/version";
    unlink $file if -f $file;
    remove_tree $dir if -d $dir;
}

sub gen_snapshot {
    my $snapshot = Carton::Snapshot->new(path => "cpanfile.snapshot");
    my $no_exclude = CPAN::Meta::Requirements->new;
    $snapshot->find_installs("local", $no_exclude);
    $snapshot->save;
}

sub git_info {
    my $describe = `git describe --tags --dirty`;
    chomp $describe;
    my $hash = `git rev-parse --short HEAD`;
    chomp $hash;
    my $url = "https://github.com/skaji/cpm/tree/$hash";
    ($describe, $url);
}

sub inject_git_info {
    my ($file, $describe, $url) = @_;
    my $inject = <<~"___";
    use App::cpm;
    \$App::cpm::GIT_DESCRIBE = '$describe';
    \$App::cpm::GIT_URL = '$url';
    ___
    my $content = Path::Tiny->new($file)->slurp_raw;
    $content =~ s/^use App::cpm::CLI;/$inject\nuse App::cpm::CLI;/sm;
    Path::Tiny->new($file)->spew_raw($content);
}


my $exclude = join ",", qw(
    Carp
    Digest::SHA
    ExtUtils::CBuilder
    ExtUtils::MakeMaker
    ExtUtils::MakeMaker::CPANfile
    ExtUtils::ParseXS
    File::Spec
    Module::Build::Tiny
    Module::CoreList
    Params::Check
    Perl::OSType
    Test
    Test2
    Test::Harness
);
my @extra = qw(
    Class::C3
    Devel::GlobalDestruction
    MRO::Compat
);

my $target = '5.8.1';

my ($git_describe, $git_url);
if (my $version = $ENV{CPAN_RELEASE_VERSION}) {
    $git_describe = $version;
    $git_url = "https://github.com/skaji/cpm/tree/$version";
} else {
    ($git_describe, $git_url) = git_info;
}
warn "\e[1;31m!!! GIT IS DIRTY !!!\e[m\n" if !$update_only && $git_describe =~ /dirty/;

my @copyright = Path::Tiny->new("copyrights-and-licenses.json")->lines({chomp => 1});
my $copyright = join "\n", map { "# $_" } @copyright;

my $shebang = <<"___";
#!/usr/bin/env perl
use $target;

# The following distributions are embedded into this script:
#
$copyright
___

my $resolver = -f "cpanfile.snapshot" && !$force && !$test && !$update_only ? "snapshot" : "metadb";

warn "Resolver: $resolver\n";
cpm "install", "--target-perl", $target, "--resolver", $resolver;
cpm "install", "--target-perl", $target, "--resolver", $resolver, @extra;
gen_snapshot if !$test;
remove_version_xs;
exit if $update_only;

print STDERR "FatPacking...";

my $fatpack_dir = $test ? "local" : "../lib,local";
my $output = $test ? "../cpm.test" : "../cpm";
fatpack "-q", "-o", $output, "-d", $fatpack_dir, "-e", $exclude, "--shebang", $shebang, "../script/cpm", "--cache", "$ENV{HOME}/.perl-cpm/.fatpack-cache";
print STDERR " DONE\n";
inject_git_info($output, $git_describe, $git_url);
chmod 0755, $output;
