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
<a href="https://skaji.github.io/images/cpm-v1.svg"><img src="https://skaji.github.io/images/cpm-v1.svg" alt="demo" style="max-width:100%;"></a>

cpm is a fast CPAN module installer.

cpm prepares dependencies first and performs final installation
separately. By default, it installs the requested distributions and
their runtime dependency closure.

This makes installs more stable and more predictable, especially for
larger dependency graphs and parallel work.

For tutorial, check out L<App::cpm::Tutorial>.

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
