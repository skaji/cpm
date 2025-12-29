package App::cpm::Resolver::02Packages;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::Util;
use App::cpm::version;
use CPAN::02Packages::Search;
use Cwd ();
use File::Basename ();
use File::Copy ();
use File::Path ();
use File::Spec;
use File::Temp ();
use Proc::ForkSafe;

sub new {
    my ($class, $ctx, %option) = @_;
    my $cache_dir_base = $option{cache} or die "cache option is required\n";
    my $mirror = $option{mirror} or die "mirror option is required\n";
    $mirror =~ s{/*$}{/};

    my $path = $option{path} || "${mirror}modules/02packages.details.txt.gz";
    if ($path =~ m{^https?://}) {
        my $cache_dir = $class->_cache_dir($mirror, $cache_dir_base);
        $path = $class->_fetch($ctx, $path, $cache_dir);
    } else {
        $path =~ s{^file://}{};
        -f $path or die "$path: No such file or directory\n";
    }

    my $text_file = $path =~ /\.gz$/ ? $class->_gunzip($path) : App::cpm::Util::maybe_abs($path);
    my $index = Proc::ForkSafe->wrap(sub {
        CPAN::02Packages::Search->new(file => $text_file);
    });
    bless { mirror => $mirror, path => $path, index => $index }, $class;
}

sub _cache_dir {
    my ($class, $mirror, $base) = @_;
    if ($mirror !~ m{^https?://}) {
        $mirror =~ s{^file://}{};
        $mirror = Cwd::abs_path($mirror);
        $mirror =~ s{^/}{};
    }
    $mirror =~ s{/$}{};
    $mirror =~ s/[^\w\.\-]+/%/g;
    my $dir = "$base/$mirror";
    File::Path::mkpath([$dir], 0, 0777);
    return $dir;
}

sub _fetch {
    my ($class, $ctx, $path, $cache_dir) = @_;
    my $dest = File::Spec->catfile($cache_dir, File::Basename::basename($path));
    my $res = $ctx->{http}->mirror($path => $dest);
    die "$res->{status} $res->{reason}, $path\n" if !$res->{success};
    return $dest;
}

sub _gunzip {
    my ($class, $path) = @_;
    my ($fh, $dest) = File::Temp::tempfile("perl-cpm-XXXXX",
        UNLINK => 1, SUFFIX => ".txt", EXLOCK => 0, TMPDIR => 1);
    App::cpm::Util::gunzip $path, $fh;
    close $fh;
    $dest;
}

sub resolve {
    my ($self, $ctx, $task) = @_;
    my $res = $self->{index}->call(search => $task->{package});
    if (!$res) {
        return { error => "not found, @{[$self->{path}]}" };
    }

    if (my $version_range = $task->{version_range}) {
        my $version = $res->{version} || 0;
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->{path}]}" };
        }
    }
    my $dist = App::cpm::DistNotation->new_from_dist($res->{path});
    return +{
        source => "cpan", # XXX
        distfile => $dist->distfile,
        uri => $dist->cpan_uri($self->{mirror}),
        version => $res->{version} || 0,
        package => $task->{package},
    };
}

1;
