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
chdir $FindBin::Bin;

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
    ExtUtils::MakeMaker::CPANfile
    Module::Build::Tiny
    Test::Harness
);

my $shebang = <<'___';
#!/usr/bin/env perl
use 5.10.1;
___

my $resolver = -f "cpanfile.snapshot" && !$force ? "snapshot" : "metadb";

warn "Resolver: $resolver\n";
cpm "install", "--cpanfile", "../cpanfile", "--target-perl", "5.10.1", "--resolver", $resolver;
cpm "install", "--cpanfile", "../cpanfile", "--target-perl", "5.10.1", "--resolver", $resolver, "Devel::GlobalDestruction"; # for Class::Tiny
gen_snapshot;
remove_version_xs;
print STDERR "FatPacking...";
fatpack "-q", "-o", "../cpm", "-d", "../lib,local", "-e", $exclude, "--shebang", $shebang, "../script/cpm";
print STDERR " DONE\n";
