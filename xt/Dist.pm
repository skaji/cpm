package xt::Dist;
use strict;
use warnings;
use utf8;

use CPAN::Meta;
use Path::Tiny;
use Exporter 'import';
our @EXPORT = qw(dist);

sub dist {
    my (%args) = @_;
    my $name    = $args{name};
    my $version = $args{version} || '0.0.1';

    (my $package = $name) =~ s/\W/_/g;
    my $provides = {
        $package => {
            file    => "$package.pm",
            version => $version,
        },
    };

    my $meta = CPAN::Meta->new({
        abstract => "dummy dist for $name",
        author   => ['unknown'],
        license  => ['unknown'],
        version  => $version,
        dynamic_config => 1,
        generated_by   => ['xt::CLI'],
        'meta-spec'    => {
          version => '2',
          url     => 'http://search.cpan.org/perldoc?CPAN::Meta::Spec',
        },
        release_status => 'stable',
        provides => $provides,
        %args,
    });

    my $dir = Path::Tiny->tempdir(CLEANUP => 1);
    $dir->child('META.json')->spew($meta->as_string);
    $dir->child('MANIFEST')->spew(join "\n", qw(Makefile.PL MANIFEST META.json), "$package.pm");
    $dir->child("$package.pm")->spew("package $package; our \$VERSION = $version; 1");

    $dir->child('Makefile.PL')->spew(<<"__END__");
use ExtUtils::MakeMaker;
WriteMakefile(
    NAME    => '$name',
    VERSION => '$version',
);
__END__

    return $dir;
}

1;
