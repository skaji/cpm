#!/usr/bin/env perl
BEGIN { $ENV{PERL_JSON_BACKEND} = 0 } # force JSON::PP, https://github.com/perl-carton/carton/issues/214
use 5.24.0;
use FindBin;
use lib "$FindBin::Bin/../lib";
use App::FatPacker::Simple;
use App::cpm;
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

Getopt::Long::GetOptions "f|force" => \my $force;

sub cpm {
    App::cpm->new->run(@_) == 0 or die
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

my @copyright = Path::Tiny->new("copyrights-and-licenses.json")->lines;
@copyright = map { "  $_" } @copyright;

my $shebang = <<"___";
#!/usr/bin/env perl
use $target;

=for LICENSE

The following distributions are embedded into this script:

@copyright
=cut
___

my $resolver = -f "cpanfile.snapshot" && !$force ? "snapshot" : "metacpan";

warn "Resolver: $resolver\n";
cpm "install", "--cpanfile", "../cpanfile", "--target-perl", $target, "--resolver", $resolver;
cpm "install", "--cpanfile", "../cpanfile", "--target-perl", $target, "--resolver", $resolver, @extra;
gen_snapshot;
remove_version_xs;
print STDERR "FatPacking...";
fatpack "-q", "-o", "../cpm", "-d", "../lib,local", "-e", $exclude, "--shebang", $shebang, "../script/cpm";
print STDERR " DONE\n";
