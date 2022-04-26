# cpm [![](https://github.com/skaji/cpm/workflows/test/badge.svg)](https://github.com/skaji/cpm/actions)

a fast CPAN module installer

![](https://skaji.github.io/images/cpm-Plack.svg)

## Install

There are 2 ways.

### 1) self-contained version

```sh
$ curl -fsSL https://raw.githubusercontent.com/skaji/cpm/master/cpm > cpm
$ chmod +x cpm
$ ./cpm --version
```

### 2) From CPAN

```sh
$ curl -fsSL https://raw.githubusercontent.com/skaji/cpm/master/cpm | perl - install -g App::cpm
$ cpm --version
```

## Description

cpm is a fast CPAN module installer, which uses
[Menlo](https://metacpan.org/pod/Menlo) (cpanm 2.0) in parallel.

Moreover cpm keeps the each builds of distributions in your home directory.
Then, `cpm install` will use these prebuilt distributions.
That is, if prebuilts are available, cpm never build distributions again, just copy the prebuilts into an appropriate directory.
This is (of course!) inspired by [Carmel](https://github.com/miyagawa/Carmel).

## Roadmap

See https://github.com/skaji/cpm/issues/181

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
