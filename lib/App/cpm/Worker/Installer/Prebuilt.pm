package App::cpm::Worker::Installer::Prebuilt;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

my @SKIP = (
    qr{/XML-SAX-v?[0-9\.]+\.tar\.gz$},
);

sub new {
    my $class = shift;
    bless {}, $class;
}

sub skip {
    my ($self, $uri) = @_;
    !!grep { $uri =~ $_ } @SKIP;
}

1;
