use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Resolver;
use App::cpm::Resolver::Multiplexer;
use App::cpm::Resolver::MetaDB;

my $impl = App::cpm::Resolver::Multiplexer->new;
$impl->append(App::cpm::Resolver::MetaDB->new(cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/package"));
my $r = App::cpm::Worker::Resolver->new(impl => $impl);

my $res = $r->work(+{ package => "Plack", version => 1 });

like $res->{distfile}, qr/Plack/;
ok exists $res->{version};

done_testing;
