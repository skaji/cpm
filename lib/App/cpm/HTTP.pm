package App::cpm::HTTP;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm;
use HTTP::Tinyish;

{
    package App::cpm::HTTP::_HTTPTiny;
    $INC{"App/cpm/HTTP/_HTTPTiny.pm"} = __FILE__;
    use parent 'HTTP::Tinyish::Base';
    use HTTP::Tiny;
    my %supports = (http => 1);
    sub configure () {
        my %meta = ("HTTP::Tiny" => $HTTP::Tiny::VERSION);
        $supports{https} = HTTP::Tiny->can_ssl;
        \%meta;
    }
    sub supports ($self, $scheme) { $supports{$scheme} }
    sub new ($class, %argv) {
        bless { _conns => {}, _new_argv => \%argv }, $class;
    }
    sub _tiny ($self, $url) {
        my ($key) = $url =~ m{^(https?://[^/]+)};
        $key ||= "_";
        $self->{_conns}{$key} ||= HTTP::Tiny->new(%{$self->{_new_argv}});
    }
    sub request ($self, $method, $url, @argv) {
        $self->_tiny($url)->request($method, $url, @argv);
    }
    sub mirror ($self, $url, @argv) {
        $self->_tiny($url)->mirror($url, @argv);
    }
}


sub create ($class, %args) {
    my $wantarray = wantarray;

    my @try = $args{prefer} ? @{$args{prefer}} : qw(HTTPTiny LWP Curl Wget);
    @try = map { "HTTP::Tinyish::$_" } @try;
    @try = map { $_ eq "HTTP::Tinyish::HTTPTiny" ? "App::cpm::HTTP::_HTTPTiny": $_ } @try;

    my ($backend, $tool, $desc);
    for my $try (@try) {
        my $meta = HTTP::Tinyish->configure_backend($try) or next;
        $try->supports("https") or next;
        ($tool) = sort keys %$meta;
        ($desc = $meta->{$tool}) =~ s/^(.*?)\n.*/$1/s;
        $backend = $try, last;
    }
    die "Couldn't find HTTP Clients that support https" unless $backend;

    my $http = $backend->new(
        agent => "App::cpm/$App::cpm::VERSION",
        timeout => 60,
        verify_SSL => 1,
        %args,
    );
    my $keep_alive = exists $args{keep_alive} ? $args{keep_alive} : 1;
    if ($keep_alive and $backend =~ /LWP$/) {
        $http->{ua}->conn_cache({ total_capacity => 3 });
    }

    $wantarray ? ($http, "$tool $desc") : $http;
}

1;
