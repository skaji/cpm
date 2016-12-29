#!/usr/bin/env perl
use 5.24.0;
use FindBin;
use lib "$FindBin::Bin/../lib";
use App::FatPacker::Simple;
use App::cpm;
use Config;
use File::Path 'remove_tree';
chdir $FindBin::Bin;

my $exclude = join ",", qw(
    ExtUtils::MakeMaker::CPANfile
    Module::Build::Tiny
    Test::Harness
);

my $shebang = <<'___';
#!/usr/bin/env perl
use 5.10.1;
___

sub cpm { App::cpm->new->run(@_) == 0 or die }
sub fatpack { App::FatPacker::Simple->new->parse_options(@_)->run }

sub remove_version_xs {
    my $arch = $Config{archname};
    my $file = "local/lib/perl5/$arch/version/vxs.pm";
    my $dir  = "local/lib/perl5/$arch/auto/version";
    if (-f $file) {
        warn "-> \e[33mRemove $file\e[m\n";
        unlink $file or die;
    }
    if (-d $dir) {
        warn "-> \e[33mRemove $dir\e[m\n";
        remove_tree $dir or die;
    }
}

cpm "install", "--target-perl", "5.10.1", "--cpanfile", "../cpanfile";
cpm "install", "--target-perl", "5.10.1", "Devel::GlobalDestruction"; # for Class::Tiny
remove_version_xs;
fatpack "-o", "../cpm", "-d", "../lib,local", "-e", $exclude, "--shebang", $shebang, "../script/cpm",

open my $fh, "<", "../cpm" or die;
while (<$fh>) {
    if (my ($pm) = /^\$fatpacked\{"([^"]+)\.pm"/) {
        $pm =~ s{/}{::}g;
        say "FATPACKED: $pm";
    }
}
