package App::cpm::Tutorial;
use strict;
use warnings;
our $VERSION = '0.210';
1;
__END__

=head1 NAME

App::cpm::Tutorial - How to use cpm

=head1 SYNOPSIS

  $ cpm install Module

=head1 DESCRIPTION

cpm is yet another CPAN client (like L<cpan>, L<cpanp>, and L<cpanm>),
which is fast!

=head2 How to install cpm

If you have L<cpanm>, then

  $ cpanm -nq App::cpm

If not, then

  $ curl -sL http://cpanmin.us | perl - -nq App::cpm

Moreover if you use perl 5.16+, then you can fetch I<self-contained> cpm.

  $ curl -sL https://git.io/cpm > cpm

  # you can even install modules without installing cpm
  $ curl -sL https://git.io/cpm | perl - install Plack

=head2 First step

  $ cpm install Plack

This command installs Plack into C<./local>, and you can use it by

  $ perl -I$PWD/local/lib/perl5 -MPlack -E 'say Plack->VERSION'

If you want to install modules into current INC instead of C<./local>,
then use C<--global/-g> option.

  $ cpm install --global Plack

By default, cpm outputs only C<DONE install Module> things.
If you want more verbose messages, use C<--verbose/-v> option.

  $ cpm install --verbose Plack

=head2 Second step

cpm can handle version range notation like L<cpanm>. Let's see some examples.

  $ cpm install Plack~'> 1.000, <= 2.000'
  $ cpm install Plack~'== 1.0030'
  $ cpm install Plack@1.0030  # this is an alias of ~'== 1.0030'

cpm can install dev releases (TRIAL releases).

  $ cpm install Moose@dev

  # if you prefer dev releases for not only Moose,
  # but also its dependencies, then use global --dev option
  $ cpm install --dev Moose

And cpm can install modules from git repositories directly.

  $ cpm install git://github.com/skaji/Carl.git

=head2 cpanfile and experimental git/dist syntax

If you omit arguments, and there exists C<cpanfile> in the current directory,
then cpm loads modules from cpanfile, and install them

  $ cat cpanfile
  requires 'Moose', '2.000';
  requires 'Plack', '> 1.000, <= 2.000';
  $ cpm install

Moreover if you have C<cpanfile.snapshot>,
then cpm tries to resolve distribution names from it

  $ cpm install -v
  30186 DONE resolve (0.001sec) Plack -> Plack-1.0030 (from Snapshot)
  ...

This is an experimental and fun part! cpm supports git/dist syntax in cpanfile.

  $ cat cpanfile
  requires 'Carl', git => 'git://github.com/skaji/Carl.git';
  requires 'Perl::PrereqDistributionGatherer',
    git => 'https://github.com/skaji/Perl-PrereqDistributionGatherer',
    ref => '3850305'; # ref can be revision/branch/tag

Please note that to support git/dist syntax in cpanfile wholly,
there are several TODOs.

=head2 Darkpan integration

There are CPAN modules that create I<darkpans>
(minicpan, CPAN mirror) such as L<CPAN::Mini>, L<OrePAN2>, L<Pinto>.

Such darkpans store distribution tarballs in

  DARKPAN/authors/id/A/AU/AUTHOR/Module-0.01.tar.gz

and create the I<de facto standard> index file C<02packages.details.txt.gz> in

  DARKPAN/modules/02packages.details.txt.gz

If you want to use cpm against such darkpans,
change the cpm resolver by C<--resolver/-r> option:

  $ cpm install --resolver 02packages,http://example.com/darkpan Module
  $ cpm install --resolver 02packages,file::///path/to/darkpan   Module

Sometimes, your darkpan is not whole CPAN mirror, but partial,
so some modules are missing in it.
Then append C<--resolver metadb> option to fall back to normal MetaDB resolver:

  $ cpm install \
     --resolver 02packages,http://example.com/darkpan \
     --resolver metadb \
     Module

=cut
