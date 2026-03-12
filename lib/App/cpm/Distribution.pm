package App::cpm::Distribution;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Logger;
use App::cpm::Requirement;
use App::cpm::version;
use CPAN::DistnameInfo;

use constant STATE_REGISTERED      => 0b000001;
use constant STATE_DEPS_REGISTERED => 0b000010;
use constant STATE_RESOLVED        => 0b000100; # default
use constant STATE_FETCHED         => 0b001000;
use constant STATE_CONFIGURED      => 0b010000;
use constant STATE_INSTALLED       => 0b100000;

sub new ($class, %option) {
    my $uri = delete $option{uri};
    my $distfile = delete $option{distfile};
    my $source = delete $option{source} || "cpan";
    my $provides = delete $option{provides} || [];
    bless {
        %option,
        provides => $provides,
        uri => $uri,
        distfile => $distfile,
        source => $source,
        _state => STATE_RESOLVED,
        requirements => {},
    }, $class;
}

sub requirements ($self, $phase, $req = undef) {
    if (ref $phase) {
        my $req = App::cpm::Requirement->new;
        for my $p (@$phase) {
            if (my $r = $self->{requirements}{$p}) {
                $req->merge($r);
            }
        }
        return $req;
    }
    $self->{requirements}{$phase} = $req if $req;
    $self->{requirements}{$phase} || App::cpm::Requirement->new;
}

for my $attr (qw(
    source
    directory
    meta
    uri
    provides
    ref
    static_builder
    prebuilt
)) {
    no strict 'refs';
    *$attr = sub ($self, @argv) {
        $self->{$attr} = $argv[0] if @argv;
        $self->{$attr};
    };
}
sub distfile ($self, @argv) {
    $self->{distfile} = $argv[0] if @argv;
    $self->{distfile} || $self->{uri};
}

sub distvname ($self) {
    $self->{distvname} ||= do {
        CPAN::DistnameInfo->new($self->{distfile})->distvname || $self->distfile;
    };
}

sub overwrite_provide ($self, $provide) {
    my $overwrote;
    for my $exist (@{$self->{provides}}) {
        if ($exist->{package} eq $provide->{package}) {
            $exist = $provide;
            $overwrote++;
        }
    }
    if (!$overwrote) {
        push @{$self->{provides}}, $provide;
    }
    return 1;
}

sub registered ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} |= STATE_REGISTERED;
    }
    $self->{_state} & STATE_REGISTERED;
}

sub deps_registered ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} |= STATE_DEPS_REGISTERED;
    }
    $self->{_state} & STATE_DEPS_REGISTERED;
}

sub resolved ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} = STATE_RESOLVED;
    }
    $self->{_state} & STATE_RESOLVED;
}

sub fetched ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} = STATE_FETCHED;
    }
    $self->{_state} & STATE_FETCHED;
}

sub configured ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} = STATE_CONFIGURED
    }
    $self->{_state} & STATE_CONFIGURED;
}

sub installed ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->{_state} = STATE_INSTALLED;
    }
    $self->{_state} & STATE_INSTALLED;
}

sub providing ($self, $package, $version_range = undef) {
    for my $provide (@{$self->provides}) {
        if ($provide->{package} eq $package) {
            if (!$version_range or App::cpm::version->parse($provide->{version})->satisfy($version_range)) {
                return 1;
            } else {
                my $message = sprintf "%s provides %s (%s), but needs %s\n",
                    $self->distfile, $package, $provide->{version} || 0, $version_range;
                App::cpm::Logger->log(result => "WARN", message => $message);
                last;
            }
        }
    }
    return;
}

sub equals ($self, $that) {
    $self->distfile && $that->distfile and $self->distfile eq $that->distfile;
}

1;
