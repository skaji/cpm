use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Worker::Resolver;
use App::cpm::Resolver::Cascade;
use App::cpm::Resolver::MetaDB;

my $cascade = App::cpm::Resolver::Cascade->new;
$cascade->add(App::cpm::Resolver::MetaDB->new(uri => "https://cpanmetadb.plackperl.org/v1.0/"));
my $r = App::cpm::Worker::Resolver->new(impl => $cascade);

my $res = $r->work(+{ package => "Plack", version => 1 });

like $res->{distfile}, qr/Plack/;
ok exists $res->{version};

done_testing;
