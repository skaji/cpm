package CLI;
use strict;
use warnings;
use utf8;
use Capture::Tiny 'capture';
use File::Temp 'tempdir';
use Exporter 'import';
use File::Basename ();
use File::Spec;
use Cwd 'abs_path';
our @EXPORT = qw(cpm_install with_same_local with_same_home);

my $base = abs_path( File::Spec->catdir(File::Basename::dirname(__FILE__), "..", "..") );

my $TEMPDIR = tempdir CLEANUP => 1;

{
    package Result;
    no strict 'refs';
    sub new {
        my $class = shift;
        bless {@_}, $class;
    }
    for my $attr (qw(local out err exit home logfile)) {
        *$attr = sub { shift->{$attr} };
    }
    sub log {
        my $self = shift;
        return $self->{_log} if $self->{_log};
        open my $fh, "<", $self->logfile or die "$self->{logfile}: $!";
        $self->{_log} = do { local $/; <$fh> };
    }
}

our ($_LOCAL, $_HOME);

sub with_same_local (&) {
    my $sub = shift;
    local $_LOCAL = tempdir DIR => $TEMPDIR;
    $sub->();
}
sub with_same_home (&) {
    my $sub = shift;
    local $_HOME = tempdir DIR => $TEMPDIR;
    $sub->();
}

sub cpm_install {
    my @argv = @_;
    my $local = $_LOCAL || tempdir DIR => $TEMPDIR;
    my $home  = $_HOME  || tempdir DIR => $TEMPDIR;
    if ($] < 5.010) {
        unshift @argv, "--resolver",
            'Fixed,CPAN::Meta::Requirements@2.140,Module::Build::Tiny@0.047';
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
