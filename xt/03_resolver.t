use strict;
use warnings;
use utf8;
use Test::More;
use Acme::CPAN::Installer::Worker::Resolver;

my $r = Acme::CPAN::Installer::Worker::Resolver->new(
    cpanmetadb => "https://cpanmetadb-provides.herokuapp.com",
);

my $res = $r->work(+{ package => "Plack", version => 1 });

like $res->{distfile}, qr/Plack/;
ok exists $res->{version};

done_testing;
