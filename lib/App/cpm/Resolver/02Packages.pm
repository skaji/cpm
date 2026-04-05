package App::cpm::Resolver::02Packages;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

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

sub new ($class, $ctx, %argv) {
    my $cache_dir_base = $argv{cache} or die "cache option is required\n";
    my $mirror = $argv{mirror} or die "mirror option is required\n";
    $mirror =~ s{/*$}{/};

    my $path = $argv{path} || "${mirror}modules/02packages.details.txt.gz";
    if ($path =~ m{^https?://}) {
        my $cache_dir = $class->_cache_dir($mirror, $cache_dir_base);
        $path = $class->_fetch($ctx, $path, $cache_dir);
    } else {
        $path =~ s{^file://}{};
        -f $path or die "$path: No such file or directory\n";
    }

    my $text_file = $path =~ /\.gz$/ ? $class->_gunzip($path) : App::cpm::Util::maybe_abs($path);
    my $index = Proc::ForkSafe->wrap(sub () {
        CPAN::02Packages::Search->new(file => $text_file);
    });
    bless { mirror => $mirror, path => $path, index => $index }, $class;
}

sub _cache_dir ($class, $mirror, $base) {
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

sub _fetch ($class, $ctx, $path, $cache_dir) {
    my $dest = File::Spec->catfile($cache_dir, File::Basename::basename($path));
    my $res = $ctx->{http}->mirror($path => $dest);
    die "$res->{status} $res->{reason}, $path\n" if !$res->{success};
    return $dest;
}

sub _gunzip ($class, $path) {
    my ($fh, $dest) = File::Temp::tempfile("perl-cpm-XXXXX",
        UNLINK => 1, SUFFIX => ".txt", EXLOCK => 0, TMPDIR => 1);
    my ($ok, $err) = App::cpm::Util::gunzip $path, $fh;
    die $err if !$ok;
    close $fh;
    $dest;
}

sub resolve ($self, $ctx, $task) {
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
