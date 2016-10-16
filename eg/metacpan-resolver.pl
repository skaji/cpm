#!/usr/bin/env perl
use strict;
use App::cpm::Resolver::Cascade;
use App::cpm::Resolver::MetaCPAN;

my $cascade = App::cpm::Resolver::Cascade->new;
$cascade->add(App::cpm::Resolver::MetaCPAN->new);
$cascade;
