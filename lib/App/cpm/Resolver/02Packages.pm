package App::cpm::Resolver::02Packages;
use strict;
use warnings;

use App::cpm::DistNotation;
use App::cpm::HTTP;
use App::cpm::version;
use CPAN::02Packages::Search;
use Cwd ();
use File::Basename ();
use File::Copy ();
use File::Path ();
use File::Spec;
use File::Which ();
use IPC::Run3 ();

sub new {
    my ($class, %option) = @_;
    my $cache_dir_base = $option{cache} or die "cache option is required\n";
    my $mirror = $option{mirror} or die "mirror option is required\n";
    $mirror =~ s{/*$}{/};

    my $path = $option{path} || "${mirror}modules/02packages.details.txt.gz";
    my $cache_dir = $class->_cache_dir($mirror, $cache_dir_base);
    my $local_path = $class->_fetch($path => $cache_dir);

    my $index = CPAN::02Packages::Search->new(file => $local_path);
    bless { mirror => $mirror, local_path => $local_path, index => $index }, $class;
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
    my ($class, $path, $cache_dir) = @_;
    my $dest = File::Spec->catfile($cache_dir, File::Basename::basename($path));
    if ($path =~ m{^https?://}) {
        my $res = App::cpm::HTTP->create->mirror($path => $dest);
        die "$res->{status} $res->{reason}, $path\n" if !$res->{success};
    } else {
        $path =~ s{^file://}{};
        die "$path: No such file.\n" if !-f $path;
        if (!-f $dest or (stat $dest)[9] <= (stat $path)[9]) {
            File::Copy::copy($path, $dest) or die "Copy $path $dest: $!\n";
            my $mtime = (stat $path)[9];
            utime $mtime, $mtime, $dest;
        }
    }
    return $dest if $dest !~ /\.gz$/;

    my $plain = $dest;
    $plain =~ s/\.gz$//;
    if (!-f $plain or (stat $plain)[9] <= (stat $dest)[9]) {
        my $gzip = File::Which::which('gzip');
        die "Need gzip command to decompress $dest\n" if !$gzip;
        my @cmd = ($gzip, "-dc", $dest);
        IPC::Run3::run3 \@cmd, undef, $plain, \my $err;
        if ($? != 0) {
            chomp $err;
            $err ||= "exit status $?";
            die "@cmd: $err\n";
        }
    }
    return $plain
}

sub resolve {
    my ($self, $task) = @_;
    my $res = $self->{index}->search($task->{package});
    if (!$res) {
        return { error => "not found, @{[$self->{local_path}]}" };
    }

    if (my $version_range = $task->{version_range}) {
        my $version = $res->{version} || 0;
        if (!App::cpm::version->parse($version)->satisfy($version_range)) {
            return { error => "found version $version, but it does not satisfy $version_range, @{[$self->{local_path}]}" };
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
