# cpm [![Build Status](https://travis-ci.org/skaji/cpm.svg?branch=master)](https://travis-ci.org/skaji/cpm)

a fast CPAN module installer

![demo](xt/demo.gif)

## Install

There are 2 ways.

### 1) install it from CPAN

Make sure you have [cpanm](https://github.com/miyagawa/cpanminus).
If not, install it first:

```sh
$ curl -sL http://cpanmin.us | perl - -nq App::cpanminus
```

Then:

```sh
$ cpanm -nq App::cpm
```

### 2) install a self-contained version

If you have perl 5.10.1+, then you can use a _self-contained_ cpm:

```sh
$ curl -sL https://git.io/cpm > cpm
$ chmod +x cpm
$ ./cpm --version
```

## Description

cpm is a fast CPAN module installer, which uses
[Menlo](https://metacpan.org/pod/Menlo) (cpanm 2.0) in parallel.

If you're tired of installing a lot of CPAN modules, why don't you try cpm?

## Roadmap

If you all find cpm useful,
then cpm should be merged into cpanm 2.0. How exciting!

To merge cpm into cpanm, there are several TODOs:

* DONE ~~Win32? - support platforms that do not have fork(2) system call~~
* DONE ~~Logging? - the parallel feature makes log really messy~~

Your feedback is highly appreciated.

## License

Copyright 2015 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

## See Also

* [Perl Advent Calendar 2015](http://www.perladvent.org/2015/2015-12-02.html)
* [App::cpanminus](https://metacpan.org/pod/App::cpanminus)
* [Menlo](https://metacpan.org/pod/Menlo)
* [Carton](https://metacpan.org/pod/Carton)
