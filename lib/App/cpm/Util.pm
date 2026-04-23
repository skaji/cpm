package App::cpm::Util;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use Config;
use Cwd ();
use Digest::MD5 ();
use File::Spec;
use IO::Uncompress::Bunzip2 ();
use IO::Uncompress::Gunzip ();

use Exporter 'import';

our @EXPORT_OK = qw(DEBUG perl_identity maybe_abs WIN32 determine_home gunzip bunzip2 uniq);

use constant DEBUG => $ENV{PERL_CPM_DEBUG} ? 1 : 0;
use constant WIN32 => $^O eq 'MSWin32';

sub perl_identity () {
    my $digest = Digest::MD5::md5_hex($Config{perlpath} . Config->myconfig);
    $digest = substr $digest, 0, 8;
    join '-', $Config{version}, $Config{archname}, $digest
}

sub maybe_abs ($path, $cwd = undef) {
    if (File::Spec->file_name_is_absolute($path)) {
        return $path;
    }
    $cwd ||= Cwd::cwd();
    File::Spec->canonpath(File::Spec->catdir($cwd, $path));
}

sub determine_home () { # taken from Menlo
    my $homedir = $ENV{HOME}
      || eval { require File::HomeDir; File::HomeDir->my_home }
      || join('', @ENV{qw(HOMEDRIVE HOMEPATH)}); # Win32

    if (WIN32) {
        require Win32; # no fatpack
        $homedir = Win32::GetShortPathName($homedir);
    }

    File::Spec->catdir($homedir, ".perl-cpm");
}

sub gunzip ($from, $to) {
    my $ok = IO::Uncompress::Gunzip::gunzip($from, $to);
    if ($ok) {
        return (1, undef);
    }
    my $err = "gunzip($from, $to) failed: $IO::Uncompress::Gunzip::GunzipError";
    return (undef, $err);
}

sub bunzip2 ($from, $to) {
    my $ok = IO::Uncompress::Bunzip2::bunzip2($from, $to);
    if ($ok) {
        return (1, undef);
    }
    my $err = "bunzip2($from, $to) failed: $IO::Uncompress::Bunzip2::Bunzip2Error";
    return (undef, $err);
}

sub uniq (@argv) {
    my %u;
    grep !$u{$_}++, @argv;
}

1;
