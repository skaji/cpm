# cpm [![](https://github.com/skaji/cpm/workflows/test/badge.svg)](https://github.com/skaji/cpm/actions)

a fast CPAN module installer

![](https://skaji.github.io/images/cpm-v1.svg)

## Install

Download the latest self-contained cpm and run it directly:

```sh
curl -fsSL -o cpm https://github.com/skaji/cpm/releases/latest/download/cpm &&
  chmod +x cpm &&
  ./cpm --version
```

To verify its artifact attestation before running it, use this sequence
instead. It requires the [GitHub CLI](https://cli.github.com/) (`gh`)
and stops if downloading or verification fails:

```sh
curl -fsSL -o cpm https://github.com/skaji/cpm/releases/latest/download/cpm &&
  gh attestation verify cpm --repo skaji/cpm &&
  chmod +x cpm &&
  ./cpm --version
```

You can use `./cpm` as is, or place it in a directory on your `PATH`.

## Description

cpm is a fast CPAN module installer.

cpm prepares dependencies first and performs final installation
separately. By default, it installs the requested distributions and
their runtime dependency closure.

This makes installs more stable and more predictable, especially for
larger dependency graphs and parallel work.

For more background on the cpm v1 redesign, see
[cpm v1: making installs stable](https://skaji.medium.com/cpm-v1-making-installs-stable-b2236b8eda44).

## Artifact Attestations

GitHub Artifact Attestations are generated for the self-contained cpm
and release tarballs uploaded to CPAN. Verification establishes the
provenance of the downloaded artifact; it does not verify CPAN
distributions subsequently installed with cpm.

See the repository's attestations:

[https://github.com/skaji/cpm/attestations](https://github.com/skaji/cpm/attestations)

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
