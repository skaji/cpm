package App::cpm::Resolver::Mirror;
use strict;
use warnings;
use Menlo::Index::Mirror;
use File::Copy ();
use File::Path ();
use App::cpm::version;

sub new {
    my ($class, %option) = @_;
    my $mirror = $option{mirror} or die "missing mirror option";
    $mirror =~ s{/*$}{/};
    my $cache = $option{cache} || "$ENV{HOME}/.perl-cpm";
    my $index = Menlo::Index::Mirror->new({
        mirror => $mirror,
        cache => $class->source_for($mirror, $cache),
        fetcher => sub { $class->mirror(@_) },
    });
    $index->refresh_index; # refresh_index first
    bless { mirror => $mirror, index => $index }, $class;
}

# copy from Menlo::CLI::Compat
sub file_mirror {
    my($self, $uri, $path) = @_;
    my $file = $self->uri_to_file($uri);
    my $source_mtime = (stat $file)[9];
    # Don't mirror a file that's already there (like the index)
    return 1 if -e $path && (stat $path)[9] >= $source_mtime;
    File::Copy::copy($file, $path);
    utime $source_mtime, $source_mtime, $path;
}
sub uri_to_file {
    my($self, $uri) = @_;
    if ($uri =~ s!file:/+!!) {
        $uri = "/$uri" unless $uri =~ m![a-zA-Z]:!;
    }
    return $uri;
}
sub mirror {
    my($self, $uri, $local) = @_;
    if ($uri =~ /^file:/) {
        $self->file_mirror($uri, $local);
    } else {
        require HTTP::Tinyish;
        HTTP::Tinyish->new->mirror($uri, $local);
    }
}
sub source_for {
    my($self, $mirror, $cache) = @_;
    $mirror =~ s/[^\w\.\-]+/%/g;
    my $dir = "$cache/sources/$mirror";
    File::Path::mkpath([ $dir ], 0, 0777);
    return $dir;
}


sub resolve {
    my ($self, $job) = @_;
    my $result = $self->{index}->search_packages({package => $job->{package}});
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
        uri => [ "$self->{mirror}authors/id/$distfile" ],
        version => $result->{version},
        package => $result->{package},
    };
}

1;
