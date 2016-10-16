#!/usr/bin/env perl
use strict;
use App::cpm::Resolver::Cascade;
use App::cpm::Resolver::MetaDB;
use App::cpm::Resolver::Mirror;

# change as you want
my $darkpan = " http://cpan.cpantesters.org/";

my $cascade = App::cpm::Resolver::Cascade->new;
$cascade->add(App::cpm::Resolver::Mirror->new(mirror => $darkpan));
$cascade->add(App::cpm::Resolver::MetaDB->new);
$cascade;
