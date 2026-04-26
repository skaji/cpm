#!/usr/bin/env perl
use v5.42;

use App::FatPacker::Simple;
use CPAN::Meta;
use File::Which ();
use FindBin;
use Getopt::Long ();
use JSON::XS ();
use Path::Tiny ();

use lib "$FindBin::Bin/../lib";
use App::cpm::CLI;

chdir $FindBin::Bin;

Getopt::Long::GetOptions
    "f|force" => \my $force,
    "t|test" => \my $test,
    "u|update-only" => \my $update_only,
or exit 1;

my $perl_gzip_script = File::Which::which("perl-gzip-script") or die;

my sub perl_gzip_script (@argv) {
    my $exit = system $perl_gzip_script, @argv;
    $exit == 0  or die;
}

my sub cpm (@argv) {
    App::cpm::CLI->new->run(@argv) == 0 or die
}

my sub fatpack (@argv) {
    App::FatPacker::Simple->new->parse_options(@argv)->run
}

my sub generate_index (@argv) {
    my $exit = system "perl-cpan-index-generate", @argv;
    $exit == 0 or die;
}

my sub git_info () {
    my $describe = `git describe --tags --dirty`;
    chomp $describe;
    my $hash = `git rev-parse --short HEAD`;
    chomp $hash;
    my $url = "https://github.com/skaji/cpm/tree/$hash";
    ($describe, $url);
}

my sub inject_git_info ($file, $describe, $url) {
    my $inject = <<~"___";
    use App::cpm;
    \$App::cpm::GIT_DESCRIBE = '$describe';
    \$App::cpm::GIT_URL = '$url';
    ___
    my $content = Path::Tiny->new($file)->slurp_raw;
    $content =~ s/^use App::cpm::CLI;/$inject\nuse App::cpm::CLI;/sm;
    Path::Tiny->new($file)->spew_raw($content);
}

my $target = 'v5.24';

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
}

warn "Resolver: @resolver\n";
my @dependency = sort keys CPAN::Meta->load_file("../META.json")->prereqs->{runtime}{requires}->%*;
push @dependency, 'ExtUtils::PL2Bat';
cpm "install", "--target-perl", $target, @resolver, @dependency;
generate_index "local/lib/perl5", "--output", "index.txt" if !$test;
exit if $update_only;

print STDERR "FatPacking...";

my $fatpack_dir = $test ? "local" : "../lib,local";
my $output = $test ? "../cpm.test" : "../cpm";
fatpack "-q", "-o", $output, "-d", $fatpack_dir, "../script/cpm", "--cache", "$ENV{HOME}/.perl-cpm/.fatpack-cache";
print STDERR " DONE\n";
inject_git_info($output, $git_describe, $git_url);
chmod 0755, $output;
perl_gzip_script "--in-place", "--shebang", $shebang, $output;
