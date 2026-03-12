package CLI;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use utf8;
use Capture::Tiny 'capture';
use File::Temp 'tempdir';
use Exporter 'import';
use File::Basename ();
use File::Spec;
use Cwd 'abs_path';
use Sub::Util 'set_prototype';
our @EXPORT = qw(cpm_install with_same_local with_same_home);

my $base = abs_path( File::Spec->catdir(File::Basename::dirname(__FILE__), "..", "..") );

my $TEMPDIR = tempdir CLEANUP => 1;

package Result {
    no strict 'refs';
    sub new ($class, %argv) {
        bless \%argv, $class;
    }
    for my $attr (qw(local out err exit home logfile)) {
        *$attr = sub ($self) { $self->{$attr} };
    }
    sub log ($self) {
        return $self->{_log} if $self->{_log};
        open my $fh, "<", $self->logfile or die "$self->{logfile}: $!";
        $self->{_log} = do { local $/; <$fh> };
    }
}

our ($_LOCAL, $_HOME);

sub with_same_local ($sub) {
    local $_LOCAL = tempdir DIR => $TEMPDIR;
    $sub->();
}
sub with_same_home ($sub) {
    local $_HOME = tempdir DIR => $TEMPDIR;
    $sub->();
}
set_prototype '&', \&with_same_local;
set_prototype '&', \&with_same_home;

sub cpm_install (@argv) {
    my $local = $_LOCAL || tempdir DIR => $TEMPDIR;
    my $home  = $_HOME  || tempdir DIR => $TEMPDIR;
    if ($] < 5.010) {
        unshift @argv, "--resolver",
            'Fixed,CPAN::Meta::Requirements@2.140';
    }
    my ($out, $err, $exit) = capture {
        local %ENV = %ENV;
        delete $ENV{$_} for grep /^PERL_CPM_/, keys %ENV;
        system $^X, "-I$base/lib", "$base/script/cpm", "install", "-L", $local, "--home", $home, @argv;
    };
    my $logfile = "$home/build.log";
    Result->new(home => $home, local => $local, out => $out, err => $err, exit => $exit, logfile => $logfile);
}


1;
