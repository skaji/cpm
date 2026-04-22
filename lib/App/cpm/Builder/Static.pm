package App::cpm::Builder::Static;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use ExtUtils::Config;
use ExtUtils::Helpers qw(make_executable man1_pagename man3_pagename);
use ExtUtils::Install qw(pm_to_blib);
use ExtUtils::InstallPaths;
use File::Basename qw(dirname);
use File::Find ();
use File::Path qw(mkpath);
use File::Spec::Functions qw(abs2rel catdir catfile rel2abs);

use parent 'App::cpm::Builder::Base';

my sub find_files ($pattern, $dir) {
    my @files;
    File::Find::find(sub {
        return if !-f;
        push @files, $File::Find::name if /$pattern/;
    }, $dir) if -d $dir;
    return @files;
}

my sub read_file ($filename) {
    open my $fh, '<', $filename or die "Could not open $filename: $!\n";
    return do { local $/; <$fh> };
}

my sub contains_pod ($file) {
    return if !-T $file;
    return read_file($file) =~ /^\=(?:head|pod|item)/m;
}

my sub manify ($input_file, $output_file, $section) {
    return if -e $output_file && -M $input_file <= -M $output_file;
    my $dirname = dirname($output_file);
    mkpath($dirname) if !-d $dirname;
    require Pod::Man;
    Pod::Man->new(section => $section)->parse_from_file($input_file, $output_file);
    return;
}

my sub script_files () {
    return (
        grep { !/\.pod\z/ } find_files(qr/.+/, 'script'),
    );
}

my sub script_doc_files () {
    return (
        grep { /\.pod\z/ } find_files(qr/.+/, 'script'),
    );
}

my sub share_files ($dist_name) {
    return (
        map { $_ => catfile(qw(blib lib auto share dist), $dist_name, abs2rel($_, 'share')) }
            find_files(qr/.+/, 'share'),
        map { $_ => catfile(qw(blib lib auto share module), abs2rel($_, 'module-share')) }
            find_files(qr/.+/, 'module-share'),
    );
}

my sub build_manpages ($install_paths, $config, $modules, $scripts) {
    if ($install_paths->install_destination('bindoc') && $install_paths->is_default_installable('bindoc')) {
        my $section = $config->get('man1ext');
        for my $input ($scripts->@*, script_doc_files()) {
            next if !contains_pod($input);
            manify($input, catfile('blib', 'bindoc', man1_pagename($input)), $section);
        }
    }
    if ($install_paths->install_destination('libdoc') && $install_paths->is_default_installable('libdoc')) {
        my $section = $config->get('man3ext');
        for my $input ($modules->@*) {
            next if !contains_pod($input);
            manify($input, catfile('blib', 'libdoc', man3_pagename($input)), $section);
        }
    }
}

sub supports ($class, $meta) {
    return $meta->{x_static_install} && $meta->{x_static_install} == 1;
}

sub configure ($self, $ctx) {
    $self->meta->save(@$_) for ['MYMETA.json'], [ 'MYMETA.yml' => { version => 1.4 } ];
    return 1;
}

sub build ($self, $ctx) {
    $self->run_build($ctx, sub {
        my @module = find_files(qr/\.(?:pm|pod)\z/, 'lib');
        my @script = script_files();
        my %file = (
            (map { $_ => catfile('blib', $_) } @module),
            (map { $_ => catfile('blib', $_) } @script),
            share_files($self->meta->name),
        );
        pm_to_blib(\%file, catdir(qw(blib lib auto)));
        make_executable($_) for grep { m{\Ablib/script/} } values %file;
        mkpath(catdir(qw(blib arch)));
        build_manpages($self->_install_paths, ExtUtils::Config->new, \@module, \@script) if $self->{man_pages};
        return 1;
    });
}

sub test ($self, $ctx) {
    $self->run_test($ctx, sub {
        return 1 if !-d 't';
        require TAP::Harness::Env;
        my $tester = TAP::Harness::Env->create({
            color => -t STDOUT ? 1 : 0,
            lib => [ map { rel2abs(catdir(qw(blib), $_)) } qw(arch lib) ],
        });
        return !$tester->runtests(sort find_files(qr/\.t\z/, 't'))->has_errors;
    });
}

sub install ($self, $ctx) {
    $self->run_install($ctx, sub {
        ExtUtils::Install::install($self->_install_paths->install_map, 0, 0, 0);
        return 1;
    });
}

sub _install_paths ($self) {
    ExtUtils::InstallPaths->new(
        dist_name => $self->meta->name,
        ($self->{install_base} ? (install_base => $self->{install_base}) : ()),
    );
}

1;

=head1 COPYRIGHT AND LICENSE

This module is based on L<Module::Build::Tiny|https://metacpan.org/dist/Module-Build-Tiny>.
Its COPYRIGHT AND LICENSE is:

This software is copyright (c) 2011 by Leon Timmermans, David Golden.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
