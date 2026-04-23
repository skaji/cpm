package App::cpm::Distribution;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Logger;
use App::cpm::Requirement;
use App::cpm::version;
use CPAN::DistnameInfo;

use constant STATE_RESOLVED   => "resolved";
use constant STATE_FETCHED    => "fetched";
use constant STATE_CONFIGURED => "configured";
use constant STATE_BUILT      => "built";
use constant STATE_TESTED     => "tested";
use constant STATE_INSTALLED  => "installed";

sub new ($class, %argv) {
    my $uri = delete $argv{uri};
    my $distfile = delete $argv{distfile};
    my $source = delete $argv{source} || "cpan";
    my $provides = delete $argv{provides} || [];
    bless {
        %argv,
        provides => $provides,
        uri => $uri,
        distfile => $distfile,
        source => $source,
        _state => STATE_RESOLVED,
        registered => 0,
        deps_registered => 0,
        requirements => {},
    }, $class;
}

sub _set_state ($self, $state) {
    $self->{_state} = $state;
    $self->{registered} = 0;
    $self->{deps_registered} = 0;
}

sub requirements ($self, $phase, $req = undef) {
    if (ref $phase) {
        my $req = App::cpm::Requirement->new;
        for my $p ($phase->@*) {
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
    builder
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
    for my $exist ($self->{provides}->@*) {
        if ($exist->{package} eq $provide->{package}) {
            $exist = $provide;
            $overwrote++;
        }
    }
    if (!$overwrote) {
        push $self->{provides}->@*, $provide;
    }
    return 1;
}

sub registered ($self, @argv) {
    $self->{registered} = $argv[0] ? 1 : 0 if @argv;
    $self->{registered};
}

sub deps_registered ($self, @argv) {
    $self->{deps_registered} = $argv[0] ? 1 : 0 if @argv;
    $self->{deps_registered};
}

sub resolved ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_RESOLVED);
    }
    $self->{_state} eq STATE_RESOLVED;
}

sub fetched ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_FETCHED);
    }
    $self->{_state} eq STATE_FETCHED;
}

sub configured ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_CONFIGURED);
    }
    $self->{_state} eq STATE_CONFIGURED;
}

sub built ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_BUILT);
    }
    $self->{_state} eq STATE_BUILT;
}

sub tested ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_TESTED);
    }
    $self->{_state} eq STATE_TESTED;
}

sub installed ($self, @argv) {
    if (@argv && $argv[0]) {
        $self->_set_state(STATE_INSTALLED);
    }
    $self->{_state} eq STATE_INSTALLED;
}

sub providing ($self, $package, $version_range = undef) {
    for my $provide ($self->provides->@*) {
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
