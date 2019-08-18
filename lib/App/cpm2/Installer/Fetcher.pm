package App::cpm2::Installer::Fetcher;
use strict;
use warnings;

use File::Basename ();
use File::Path ();
use File::Spec;
use HTTP::Tiny;

sub new {
    my ($class, %argv) = @_;
    my $http = HTTP::Tiny->new(timeout => 10);
    my $home = $argv{home};
    File::Path::mkpath $home if !-d $home;
    bless { http => $http, home => $home }, $class;
}

sub _local_file {
    my ($self, $url) = @_;

    if ($url =~ s{^\Qhttps://cpan.metacpan.org/}{}) {
        my $dirname  = File::Basename::dirname $url;
        my $basename = File::Basename::basename $url;
        return map File::Spec->catdir($self->{home}, "cpan.metacpan.org", $_), $dirname, $basename;
    } else {
        die;
    }
}

sub _mkpath {
    my ($self, $dir) = @_;
    for (1..2) {
        return 1 if -d $dir;
        File::Path::mkpath $dir;
    }
    die if !-d $dir;
}

sub fetch {
    my ($self, $url) = @_;
    my ($dir, $file) = $self->_local_file($url);
    $self->_mkpath($dir);
    my $res = $self->{http}->mirror($url, $file);

    if (!$res->{success}) {
        unlink $file;
        return (undef, "$url, $res->{status} $res->{reason}");
    }
    return $file;
}

1;
