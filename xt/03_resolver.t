use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Resolver;

my $r = App::cpm::Worker::Resolver->new(
    resolver => [
        {cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/package"},
    ],
);

my $res = $r->work(+{ package => "Plack", version => 1 });

like $res->{distfile}, qr/Plack/;
ok exists $res->{version};

done_testing;
