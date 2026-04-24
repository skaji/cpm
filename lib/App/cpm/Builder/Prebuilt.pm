package App::cpm::Builder::Prebuilt;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use parent 'App::cpm::Builder::Base';

use ExtUtils::Install ();

sub new ($class, %args) {
    my $self = $class->SUPER::new(%args);
    $self->_prepare_paths_cache;
    return $self;
}

sub test ($self, $ctx) {
    die ref($self) . " does not implement test";
}

1;
