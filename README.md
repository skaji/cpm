# NAME

Acme::CPAN::Installer - an experimental cpan module installer

# SYNOPSIS

    > cpan-installer install Module1 Module2 ...

    # from cpanfile
    > cpan-installer install

# INSTALL

This module depends on [Menlo::CLI::Compat](https://github.com/miyagawa/cpanminus/tree/menlo),
so you have to install it first:

    > cpanm git://github.com/miyagawa/cpanminus.git@menlo

Then install this module:

    > cpanm git://github.com/shoichikaji/Acme-CPAN-Installer.git

# DESCRIPTION

Acme::CPAN::Installer is an experimental cpan module installer,
which uses Menlo::CLI::Compat in parallel.

# MOTIVATION

My motivation is simple: I want to install cpan modules as quickly as possible.

# WHY INSTALLATION OF CPAN MODULES IS SO HARD

I think the hardest part of installation of cpan modules is that
cpan world has two notions **modules** and **distributions**,
and cpan clients must handle these correspondence correctly.

I suspect this only applies to cpan world,
and never applies to, for example, ruby gems or node npm.

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
