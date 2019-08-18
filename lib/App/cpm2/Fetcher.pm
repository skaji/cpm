package App::cpm2::Fetcher;
use strict;
use warnings;

use File::Basename ();
use File::Path ();
use File::Spec;
use HTTP::Tiny;

sub new {
    my $class = shift;
    my $http = HTTP::Tiny->new(timeout => 10);

    my $base = File::Spec->catdir($ENV{HOME}, ".cpm2", "cache");
    File::Path::mkpath $base if !-d $base;

    bless { http => $http, base => $base }, $class;
}

sub fetch {
    my ($self, $url) = @_;
    my $file = File::Spec->catfile($self->{base}, File::Basename::basename $url);
    my $res = $self->{http}->mirror($url, $file);

    if (!$res->{success}) {
        unlink $file;
        return (undef, "$url, $res->{status} $res->{reason}");
    }
    return $file;
}

1;
