package App::cpm::Worker::Installer::Custom;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use YAML::PP ();

sub new ($class, %argv) {
    bless { custom => [], %argv }, $class;
}

sub new_from_file ($class, $path) {
    my ($data) = YAML::PP->new->load_file($path);
    my @custom = $data->{distribution_custom} ? $data->{distribution_custom}->@* : ();
    for my $c (@custom) {
        $c->{match} = qr/$c->{match}/;
    }
    $class->new(custom => \@custom);
}

sub config ($self, $dist_uri) {
    for my $c ($self->{custom}->@*) {
        if ($dist_uri =~ $c->{match}) {
            return $c->{config};
        }
    }
    return;
}

sub merge ($self, $other) {
    my $class = ref $self;
    $class->new(custom => [ $self->{custom}->@*, $other->{custom}->@* ]);
}

sub default ($class) {
    $class->new(custom => [
        {
            match => qr{/G/GR/GRANTM/XML-SAX-[\d.]+\.tar\.gz$},
            config => {
                prebuilt => 0,
                use_install_command => 1,
            },
        },
    ]);
}

1;
