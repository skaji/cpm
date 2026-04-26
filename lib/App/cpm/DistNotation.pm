package App::cpm::DistNotation;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

my $A1 = q{[A-Z]};
my $A2 = q{[A-Z]{2}};
my $AUTHOR = qr{[A-Z]{2}[\-A-Z0-9]*};

our $CPAN_URI = qr{^(.*)/authors/id/($A1/$A2/$AUTHOR/.*)$}o;
our $DISTFILE = qr{^(?:$A1/$A2/)?($AUTHOR)/(.*)$}o;

sub new ($class) {
    bless {
        mirror => '',
        distfile => '',
    }, $class;
}

sub new_from_dist ($class, $dist) {
    my $self = $class->new;
    if ($dist =~ $DISTFILE) {
        my $author = $1;
        my $rest = $2;
        $self->{distfile} = sprintf "%s/%s/%s/%s",
            substr($author, 0, 1), substr($author, 0, 2), $author, $rest;
        return $self;
    }
    return;
}

sub new_from_uri ($class, $uri) {
    my $self = $class->new;
    if ($uri =~ $CPAN_URI) {
        $self->{mirror} = $1;
        $self->{distfile} = $2;
        return $self;
    }
    return;
}

sub cpan_uri ($self, $mirror = undef) {
    $mirror ||= $self->{mirror};
    $mirror =~ s{/+$}{};
    sprintf "%s/authors/id/%s", $mirror, $self->{distfile};
}

sub distfile ($self) { $self->{distfile} }

1;
