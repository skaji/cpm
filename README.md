[![Build Status](https://travis-ci.org/shoichikaji/cpm.svg?branch=master)](https://travis-ci.org/shoichikaji/cpm)

# NAME

App::cpm - a fast cpan module installer

# SYNOPSIS

    > cpm install Module

# DESCRIPTION

**THIS IS EXPERIMETNAL.**

cpm is a fast cpan module installer, which uses [Menlo::CLI::Compat](https://metacpan.org/pod/Menlo::CLI::Compat) in parallel.

# MOTIVATION

Why do we need a new cpan client?

I used [cpanm](https://metacpan.org/pod/cpanm) a lot, and it's totally awesome.

But if your Perl project has hundreds of cpan module dependencies,
then it takes quite a lot of time to install them.

So my motivation is simple: I want to install cpan modules as fast as possible.

# HOW FAST?

Just an example:

    > time cpanm -nq -Lextlib Plack
    real 0m47.705s

    > time cpm install Plack
    real 0m16.629s

This shows cpm is 3x faster than cpanm.

# COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji &lt;skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[App::cpanminus](https://metacpan.org/pod/App::cpanminus)

[Menlo](https://metacpan.org/pod/Menlo)

[Carton](https://metacpan.org/pod/Carton)
