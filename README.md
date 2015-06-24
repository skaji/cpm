# NAME

Acme::CPAN::Installer - an experimental cpan module installer

# SYNOPSIS

Install distributions listed in `cpanfile.snapshot`:

    # from cpanfile.snapshot
    > cpan-installer

Install modules specified in `cpanfile` or arguments (very experimental):

    # from cpanfile
    > cpan-installer

    # or explicitly
    > cpan-installer Module1 Module2 ...

# INSTALL

This module depends on [Menlo::CLI::Compat](https://github.com/miyagawa/cpanminus/tree/menlo),
so you have to install it first:

    > cpanm git://github.com/miyagawa/cpanminus.git@menlo

Then install this module:

    > cpanm git://github.com/shoichikaji/Acme-CPAN-Installer.git

# DESCRIPTION

Acme::CPAN::Installer is an experimental cpan module installer.

# MOTIVATION

My motivation is simple: I want to install cpan modules as quickly as possible.

# WHY INSTALLATION OF CPAN MODULES IS SO HARD

I think the hardest part of installation of cpan modules is that
cpan world has two notions **modules** and **distributions**,
and cpan clients must handle these correspondence correctly.

I suspect this only applies to cpan world,
and never applies to, for example, ruby gems or node npm.

And, the 2nd hardest part is that
we cannot determine the real dependencies of a distribution
unless we fetch it, extract it, execute `Makefile.PL`/`Build.PL`, and get `MYMETA.json`.

So I propose:

- Create an API server which offers:

        input:
          * module and its version requirement
        output:
          * distfile path
          * providing modules (modules and versions)
          * dependencies of modules (or distributions?)

    I guess this is accomplished by combining
    [http://cpanmetadb.plackperl.org/](http://cpanmetadb.plackperl.org/) and [https://api.metacpan.org/](https://api.metacpan.org/).

    Sample: [https://cpanmetadb-provides.herokuapp.com/](https://cpanmetadb-provides.herokuapp.com/)

- Forbid cpan distributions to configure themselves dynamically
so that the dependencies are determined statically.

# AUTHOR

Shoichi Kaji <skaji@cpan.org>

# COPYRIGHT

Copyright 2015- Shoichi Kaji

# LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# SEE ALSO

[App::cpanminus](https://metacpan.org/pod/App::cpanminus)

[Carton](https://metacpan.org/pod/Carton)
