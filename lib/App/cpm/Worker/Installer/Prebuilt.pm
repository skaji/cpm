package App::cpm::Worker::Installer::Prebuilt;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

my @SKIP = (
    qr{/XML-SAX-v?[0-9\.]+\.tar\.gz$},
);

sub new ($class) {
    bless {}, $class;
}

sub skip ($self, $uri) {
    !!grep { $uri =~ $_ } @SKIP;
}

1;
