package App::cpm2::Extractor;
use strict;
use warnings;

use File::pushd ();
use CPAN::Meta;
use Parse::LocalDistribution;
use File::Spec;

sub new {
    my $class = shift;
    bless {}, $class;
}
sub work {
    my ($self, $directory) = @_;

    my $parser = Parse::LocalDistribution->new({ALLOW_DEV_VERSION => 1});
    my $provides = $parser->parse($directory);

    my $meta;
    if (my ($file) = grep -f, map File::Spec->catfile($directory, $_), qw(META.json META.yml)) {
        $meta = eval { CPAN::Meta->load_file($file) };
    }
    die if !$meta;

    use DDP;
    p $meta;
    p $provides;
}

1;
