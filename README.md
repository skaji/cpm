# cpm [![](https://github.com/skaji/cpm/workflows/test/badge.svg)](https://github.com/skaji/cpm/actions)

a fast CPAN module installer

![](https://skaji.github.io/images/cpm-Plack.svg)

## Install

There are 2 ways.

### 1) self-contained version

```sh
$ curl -fsSL https://raw.githubusercontent.com/skaji/cpm/main/cpm > cpm
$ chmod +x cpm
$ ./cpm --version
```

### 2) From CPAN

```sh
$ curl -fsSL https://raw.githubusercontent.com/skaji/cpm/main/cpm | perl - install -g App::cpm
$ cpm --version
```

## Description

cpm is a fast CPAN module installer.

cpm prepares dependencies first and performs final installation
separately. By default, it installs the requested distributions and
their runtime dependency closure.

This makes installs more stable and more predictable, especially for
larger dependency graphs and parallel work.

For more background on the cpm v1 redesign, see
[cpm v1: making installs stable](https://skaji.medium.com/cpm-v1-making-installs-stable-b2236b8eda44).

## License

Copyright 2015 Shoichi Kaji <skaji@cpan.org>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

## See Also

* You may want to check [install-with-cpm](https://github.com/marketplace/actions/install-with-cpm) when you use cpm with [GitHub Actions](https://help.github.com/en/actions).
* [Perl Advent Calendar 2015](http://www.perladvent.org/2015/2015-12-02.html)
* [App::cpanminus](https://metacpan.org/pod/App::cpanminus)
* [Menlo](https://metacpan.org/pod/Menlo)
* [Carton](https://metacpan.org/pod/Carton)
