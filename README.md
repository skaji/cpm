[![Build Status](https://travis-ci.org/shoichikaji/cpm.svg?branch=master)](https://travis-ci.org/shoichikaji/cpm)

# NAME

App::cpm - an experimental cpan client

# SYNOPSIS

    > cpm install Module

# DESCRIPTION

**THIS IS VERY EXPERIMETNAL, API WILL CHANGE WITHOUT NOTICE!**

cpm is an experimental cpan client, which uses Menlo::CLI::Compat in parallel.
You may install cpan modules fast with cpm.

# MOTIVATION

Why do we need a new cpan client?

I use [cpanm](https://metacpan.org/pod/cpanm) a lot, and it's totally awesome.

But if your Perl project has hundreds of cpan module dependencies,
then it takes quite a lot of time to install them.

So my motivation is: I want to install cpan modules as fast as possible.

# HOW FAST?

Just an example:

    > time cpanm -nq -Lextlib Plack
    real 0m47.705s

    > time cpm install Plack
    real 0m16.629s

Why don't you try cpm with your favorite modules?

# COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[App::cpanminus](https://metacpan.org/pod/App::cpanminus)

[Carton](https://metacpan.org/pod/Carton)
