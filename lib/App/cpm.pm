package App::cpm v0.999.11;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

our $TRIAL = 1;
our ($GIT_DESCRIBE, $GIT_URL);

1;
__END__

=encoding utf-8

=head1 NAME

App::cpm - a fast CPAN module installer

=head1 SYNOPSIS

  > cpm install Module

=head1 DESCRIPTION

=for html
<a href="https://skaji.github.io/images/cpm-Plack.svg"><img src="https://skaji.github.io/images/cpm-Plack.svg" alt="demo" style="max-width:100%;"></a>

cpm is a fast CPAN module installer.

cpm prepares dependencies first and performs final installation
separately. By default, it installs the requested distributions and
their runtime dependency closure.

cpm keeps builds of distributions in your home directory and can reuse
them later, which also helps make large installs faster.

For tutorial, check out L<App::cpm::Tutorial>.

=head1 MOTIVATION

Why do we need a new CPAN client?

I used L<cpanm> a lot, and it's totally awesome.

But if your Perl project has hundreds of CPAN module dependencies,
then it takes quite a lot of time to install them.

Also, for a long time cpm had an installation stability problem around
partially built local libraries and changing dependency environments.

So my motivation is simple: I want to install CPAN modules as fast as
possible, and I want the install process to be stable and
predictable.

=head2 HOW FAST?

Just an example:

  > time cpanm -nq -Lextlib Plack
  real 0m47.705s

  > time cpm install Plack
  real 0m16.629s

This shows cpm can be much faster than cpanm.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Perl Advent Calendar 2015|http://www.perladvent.org/2015/2015-12-02.html>

L<App::cpanminus>

L<Menlo>

L<Carton>

L<Carmel>

=cut
