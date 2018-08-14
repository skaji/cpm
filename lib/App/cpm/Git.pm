package App::cpm::Git;
use strict;
use warnings;

use CPAN::Meta;
use File::Find ();
use File::Spec;

sub is_git_uri {
    my ($class, $uri) = @_;
    return $uri =~ /(?:^git:|\.git(?:@|\/|$))/;
}

sub split_uri {
    my ($class, $uri) = @_;
    $uri =~ s/(?<=\.git)(\/.+)$//;
    return ($uri, $1);
}

sub module_rev {
    my ($class, $filename) = @_;
    open my $f, '<', $filename or return;
    while (my $line = <$f>) {
        if ($line =~ /VERSION.*# (\p{IsXDigit}{40})$/) {
            close $f;
            return $1;
        }
    }
    close $f;
    return;
}

sub rev_is {
    my ($class, $short_rev, $long_rev) = @_;
    return $long_rev && index($long_rev, $short_rev) == 0;
}

sub version {
    my ($class, $dir) = @_;
    chomp(my $version = `git -C $dir describe --tags --match '*.*' 2>/dev/null`);
    if ($version) {
        if ($version =~ /^(\d+\.\d+)(?:-(\d+)-g\p{IsXDigit}+)?$/) {
            $version = $1 . ($2 ? sprintf "_%02d", $2 : '');
        } elsif ($version =~ /^v(\d+\.\d+)(?:-(\d+)-g\p{IsXDigit}+)?$/) {
            $version = "v$1.0" . ($2 ? ".$2" : '');
        } elsif ($version =~ /^v?(\d+\.\d+\.\d+)(?:-(\d+)-g\p{IsXDigit}+)?$/) {
            $version = "v$1" . ($2 ? ".$2" : '');
        } else {
            $version = undef;
        }
    }
    unless ($version) {
        chomp(my $time = `git -C $dir show -s --pretty=format:%at`);
        $version = sprintf "0.000_%09d", $time / 4; # divide by 4 to fit MAX_INT32 into 3 triples
    }
    return $version;
}

sub rewrite_version {
    my ($class, $dir, $version, $rev) = @_;

    foreach my $file (map File::Spec->catfile($dir, $_), 'META.json', 'META.yml') {
        next unless -f $file;
        my $meta = CPAN::Meta->load_file($file);
        $meta->{version} = $version;
        $meta->save($file);
    }

    File::Find::find(sub {
        return unless $_ =~ /\.pm$/;
        my $content = do {
            open my $f, '<', $_ or return;
            local $/ = undef;
            my $c = <$f>;
            close $f;
            $c;
        };
        $content =~ s/([\$*][\w\:\']*\bVERSION\b\s*=\s*)[^;]+;\n?/$1'$version'; # $rev\n/mso
            or $content =~ s/^(package[^;]+;)\n?/$1\nour \$VERSION = '$version'; # $rev\n/msg
            or return;
        open my $f, '>', $_ or return;
        print $f $content;
        close $f;
    }, $dir);
}

1;
