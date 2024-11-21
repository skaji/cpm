#!/usr/bin/env perl
use v5.38;
use experimental qw(builtin class defer for_list try);

use App::FatPacker::Simple;
use Config;
use FindBin;
use Getopt::Long ();
use JSON::XS ();
use Path::Tiny ();

use lib "$FindBin::Bin/../lib";
use App::cpm::CLI;

chdir $FindBin::Bin;

=for hint

Show new dependencies

    git diff cpm | perl -nle 'print $1 if /^\+\$fatpacked\{"([^"]+)/'

=cut

Getopt::Long::GetOptions
    "f|force" => \my $force,
    "t|test" => \my $test,
    "u|update-only" => \my $update_only,
or exit 1;

sub cpm (@argv) {
    App::cpm::CLI->new->run(@argv) == 0 or die
}

sub fatpack (@argv) {
    App::FatPacker::Simple->new->parse_options(@argv)->run
}

sub remove_version_xs () {
    my $arch = $Config{archname};
    my $file = "local/lib/perl5/$arch/version/vxs.pm";
    my $dir  = "local/lib/perl5/$arch/auto/version";
    unlink $file if -f $file;
    Path::Tiny->new($dir)->remove_tree({ safe => 0 }) if -d $dir;
}

sub generate_index (@argv) {
    my $exit = system "perl-cpan-index-generate", @argv;
    $exit == 0 or die;
}

sub git_info () {
    my $describe = `git describe --tags --dirty`;
    chomp $describe;
    my $hash = `git rev-parse --short HEAD`;
    chomp $hash;
    my $url = "https://github.com/skaji/cpm/tree/$hash";
    ($describe, $url);
}

sub inject_git_info ($file, $describe, $url) {
    my $inject = <<~"___";
    use App::cpm;
    \$App::cpm::GIT_DESCRIBE = '$describe';
    \$App::cpm::GIT_URL = '$url';
    ___
    my $content = Path::Tiny->new($file)->slurp_raw;
    $content =~ s/^use App::cpm::CLI;/$inject\nuse App::cpm::CLI;/sm;
    Path::Tiny->new($file)->spew_raw($content);
}

my @extra = qw(
    Class::C3
    Devel::GlobalDestruction
    ExtUtils::PL2Bat
    MRO::Compat
);

my $exclude = join ",", qw(
    CPAN::Common::Index
    CPAN::Meta::Check
    Carp
    Digest::SHA
    ExtUtils::CBuilder
    ExtUtils::MakeMaker
    ExtUtils::MakeMaker::CPANfile
    ExtUtils::ParseXS
    File::Fetch
    File::Spec
    IPC::Cmd
    Locale::Maketext::Simple
    MIME::Base32
    Module::Build::Tiny
    Module::CoreList
    Module::Load::Conditional
    Params::Check
    Perl::OSType
    Term::Table
    Test
    Test2
    Test::Harness
    URI
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

my @resolver;
if (-f "index.txt" && !$force && !$test && !$update_only) {
    @resolver = ("-r", "02packages,index.txt,https://cpan.metacpan.org/");
} else {
    @resolver = ("-r", 'Fixed,CPAN::Meta::Requirements@2.140');
}

warn "Resolver: @resolver\n";
cpm "install", "--target-perl", $target, @resolver, "--cpmfile", "../cpm.yml";
cpm "install", "--target-perl", $target, @resolver, @extra;
generate_index "local/lib/perl5", "--exclude", $exclude, "--output", "index.txt" if !$test;
remove_version_xs;
exit if $update_only;

print STDERR "FatPacking...";

my $fatpack_dir = $test ? "local" : "../lib,local";
my $output = $test ? "../cpm.test" : "../cpm";
fatpack "-q", "-o", $output, "-d", $fatpack_dir, "-e", $exclude, "--shebang", $shebang, "../script/cpm", "--cache", "$ENV{HOME}/.perl-cpm/.fatpack-cache";
print STDERR " DONE\n";
inject_git_info($output, $git_describe, $git_url);
chmod 0755, $output;
