package App::cpm::Resolver::O2Packages;
use strict;
use warnings;
use App::cpm::version;
use Cwd ();
use File::Path ();
use File::Temp ();

{
    package
        App::cpm::Resolver::O2Packages::Impl;
    use parent 'CPAN::Common::Index::Mirror';
    use Class::Tiny qw(index);
    use IO::Uncompress::Gunzip ();
    use File::Spec;
    use File::Basename ();
    use File::Copy ();
    use HTTP::Tinyish;

    sub cached_package { shift->{cached_package} }

    sub refresh_index {
        my $self = shift;
        my $index = $self->index;
        my $dest = File::Spec->catfile($self->cache, File::Basename::basename($index));
        if ($index =~ m{^https?://}) {
            my $res = HTTP::Tinyish->new->mirror($index => $dest);
            die "$res->{status} $res->{reason}, $index\n" unless $res->{success};
        } else {
            $index =~ s{^file://}{};
            if (!-f $dest or (stat $dest)[9] > (stat $index)[9]) {
                File::Copy::copy($index, $dest) or die "Copy $index $dest: $!\n";
                my $mtime = (stat $index)[9];
                utime $mtime, $mtime, $dest;
            }
        }

        if ($dest =~ /\.gz$/) {
            ( my $uncompressed = File::Basename::basename($dest) ) =~ s/\.gz$//;
            $uncompressed = File::Spec->catfile( $self->cache, $uncompressed );
            if ( !-f $uncompressed or (stat $dest)[9] > (stat $uncompressed)[9] ) {
                IO::Uncompress::Gunzip::gunzip($dest, $uncompressed)
                    or die "Gunzip $dest: $IO::Uncompress::Gunzip::GunzipError";
            }
            $self->{cached_package} = $uncompressed;
        } else {
            $self->{cached_package} = $dest;
        }
    }
}

sub new {
    my ($class, %option) = @_;
    my $cache_base = $option{cache} || "$ENV{HOME}/.perl-cpm";
    my $mirror = $option{mirror};
    $mirror =~ s{/*$}{/};

    my ($index, $cache);
    if ($option{index}) {
        $index = $option{index};
        $cache = File::Temp::tempdir(CLEANUP => 1);
    } else {
        $index = "${mirror}modules/02packages.details.txt.gz";
        $cache = $class->cache_for($mirror, $cache_base);
    }

    my $impl = App::cpm::Resolver::O2Packages::Impl->new(
        index => $index, cache => $cache,
    );
    $impl->refresh_index; # refresh_index first
    bless { mirror => $mirror, impl => $impl }, $class;
}

sub cache_for {
    my ($class, $mirror, $cache) = @_;
    if ($mirror !~ m{^https?://}) {
        $mirror =~ s{^file://}{};
        $mirror = Cwd::abs_path($mirror);
    }
    $mirror =~ s{^/}{};
    $mirror =~ s/[^\w\.\-]+/%/g;
    my $dir = "$cache/sources/$mirror";
    File::Path::mkpath([ $dir ], 0, 0777);
    return $dir;
}

sub resolve {
    my ($self, $job) = @_;
    my $result = $self->{impl}->search_packages({package => $job->{package}});
    return unless $result;

    if (my $req_version = $job->{version}) {
        my $version = $result->{version};
        if (!App::cpm::version->parse($version)->satisfy($req_version)) {
            return;
        }
    }
    my $distfile = $result->{uri};
    $distfile =~ s{^cpan:///distfile/}{};
    $distfile =~ m{^((.).)};
    $distfile = "$2/$1/$distfile";
    return +{
        source => "cpan", # XXX
        distfile => $distfile,
        uri => "$self->{mirror}authors/id/$distfile",
        version => $result->{version},
        package => $result->{package},
    };
}

1;
