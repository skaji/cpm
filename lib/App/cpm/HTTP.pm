package App::cpm::HTTP;
use strict;
use warnings;
use HTTP::Tinyish;

our $VERSION = '0.966';

sub _configure {
    my ($class, %args) = @_;

    my $want_ssl = exists $args{_ssl} ? $args{_ssl} : 1;

    my @try = qw(HTTPTiny LWP Curl Wget);
    my $backend;
    for my $try (map "HTTP::Tinyish::$_", @try) {
        if (my $meta = HTTP::Tinyish->configure_backend($try)) {
            next if $want_ssl and !$try->supports('https');
            $backend = $try, last;
        }
    }
    $backend->new(%args);
}

sub new {
    my ($class, %args) = @_;
    my $http = $class->_configure(
        keep_alive => 1,
        timeout => 60,
        agent => "App::cpm/$VERSION",
        verify_SSL => 1,
        %args,
    );
    bless { http => $http }, $class;
}

for my $method (qw(get post mirror)) {
    no strict 'refs';
    *$method = sub { shift->{http}->$method(@_) };
}

1;
