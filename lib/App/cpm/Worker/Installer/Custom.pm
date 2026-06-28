package App::cpm::Worker::Installer::Custom;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

my @CUSTOM = (
    {
        match => qr{/G/GR/GRANTM/XML-SAX-[\d.]+\.tar\.gz$},
        config => {
            prebuilt => 0,
            use_install_command => 1,
        },
    },
);

sub new ($class) {
    bless {}, $class;
}

sub config ($self, $dist_uri) {
    for my $c (@CUSTOM) {
        if ($dist_uri =~ $c->{match}) {
            return $c->{config};
        }
    }
    return;
}

1;
