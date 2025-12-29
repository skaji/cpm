use strict;
use warnings;
use utf8;
use Test::More;
use App::cpm::Context;
use App::cpm::Resolver::Cascade;
use App::cpm::Resolver::MetaDB;
use App::cpm::Worker::Resolver;

my $ctx = App::cpm::Context->new;
my $cascade = App::cpm::Resolver::Cascade->new($ctx);
$cascade->add(App::cpm::Resolver::MetaDB->new($ctx, uri => "https://cpanmetadb.plackperl.org/v1.0/"));
my $r = App::cpm::Worker::Resolver->new($ctx, impl => $cascade);

my $res = $r->work($ctx, +{ package => "Plack", version => 1 });

like $res->{distfile}, qr/Plack/;
ok exists $res->{version};

done_testing;
