package App::cpm2::Installer::Util;
use strict;
use warnings;

use File::Spec ();
use File::pushd ();
use IPC::Run3 ();

use Exporter 'import';
our @EXPORT_OK = qw(execute);


sub execute {
    my ($eslf, %argv) = @_;

    my $cmd = $argv{cmd};
    my $lib = $argv{lib};
    my $bin = $argv{bin};
    my $env = $argv{env} || +{};
    my $log = $argv{log};
    my $dir = $argv{dir};

    my @extra;

    my $guard = File::pushd::pushd $dir if $dir;
    push @extra, "dir $dir" if $dir;

    local %ENV = (%ENV, %$env);
    if ($lib || $bin) {
        my $PERL5LIB = join ":", @$lib, (split /:/, $ENV{PERL5LIB} || "");
        my $PATH = join ":", @$lib, (split /:/, $ENV{PATH} || "");
        $ENV{PERL5LIB} = $PERL5LIB;
        $ENV{PATH} = $PATH;
        push @extra, "PERL5LIB $PERL5LIB, PATH $PATH";
    }

    my $extra = " with " . join ", ", @extra;
    $log->("Executing @$cmd$extra");

    my $out;
    IPC::Run3::run3 $cmd, undef, \$out, \$out;
    my $exit = $?;
    $log->($out);
    return $exit == 0;
}

sub nonempty {
    my @dir = @_;

    while (defined(my $dir = shift @dir)) {
        opendir my $dh, $dir or return;
        my @entry =
            map File::Spec->catfile($dir, $_),
            grep $_ ne "." && $_ ne ".." && $_ ne ".exists" && $_ ne ".keep", readdir $dh;
        return 1 if grep -f, @entry;
        push @dir, grep -d, @entry;
    }
    return;
}

1;
