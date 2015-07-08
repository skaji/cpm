package Acme::CPAN::Installer;

use strict;
use warnings;
use 5.008_005;
our $VERSION = '0.01';

use Acme::CPAN::Installer::Master;
use Acme::CPAN::Installer::Worker;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use Pod::Usage ();
use Cwd 'abs_path';
use Config;

sub new {
    my ($class, %option) = @_;
    bless {
        workers => 5,
        snapshot => "cpanfile.snapshot",
        cpanfile => "cpanfile",
        local_lib => "local",
        cpanmetadb => "https://cpanmetadb-provides.herokuapp.com",
        mirror => "http://www.cpan.org",
        %option
    }, $class;
}

sub parse_options {
    my ($self, @argv) = @_;
    local @ARGV = @argv;
    GetOptions
        "L|local-lib-contained=s" => \($self->{local_lib}),
        "w|workers=i" => \($self->{workers}),
        "g|global"    => \($self->{global}),
        "v|verbose"   => \($self->{verbose}),
        "h|help"      => sub { $self->cmd_help },
        "V|version"   => sub { $self->cmd_version },
        "cpanmetadb=s" => \($self->{cpanmetadb}),
        "mirror=s"     => \($self->{mirror}),
    or exit 1;
    $self->{local_lib} = abs_path $self->{local_lib} unless $self->{global};
    $self->{packages} = [ map +{ package => $_, version => 0 }, @ARGV ];
    s{/$}{} for $self->{cpanmetadb}, $self->{mirror};
    @ARGV;
}

sub _search_inc {
    my $self = shift;
    return @INC if $self->{global};
    my $base = $self->{local_lib};
    # copy from cpanminus
    require local::lib;
    (
        local::lib->resolve_path(local::lib->install_base_arch_path($base)),
        local::lib->resolve_path(local::lib->install_base_perl_path($base)),
        (!$self->{exclude_vendor} ? grep {$_} @Config{qw(vendorarch vendorlibexp)} : ()),
        @Config{qw(archlibexp privlibexp)},
    );
}

sub run {
    my ($self, @argv) = @_;
    my $cmd = shift @argv or die "Need subcommand, try `$0 --help`\n";
    $cmd = "help"    if $cmd =~ /^(-h|--help)$/;
    $cmd = "version" if $cmd =~ /^(-V|--version)$/;
    if (my $sub = $self->can("cmd_$cmd")) {
        @argv = $self->parse_options(@argv) unless $cmd eq "exec";
        return $self->$sub(@argv);
    } else {
        die "Unknown command: $cmd\n";
    }
}

sub cmd_help {
    Pod::Usage::pod2usage(0);
}
sub cmd_version {
    my $class = ref $_[0] || $_[0];
    printf "%s %s\n", $class, $class->VERSION;
    exit 0;
}

sub cmd_exec {
    my ($self, @argv) = @_;
    my $local_lib = abs_path $self->{local_lib};
    if (-d "$local_lib/lib/perl5") {
        $ENV{PERL5LIB} = "$local_lib/lib/perl5"
                       . ($ENV{PERL5LIB} ? ":$ENV{PERL5LIB}" : "");
    }
    if (-d "$local_lib/bin") {
        $ENV{PATH} = "$local_lib/bin:$ENV{PATH}";
    }
    exec @argv;
    exit 255;
}

sub cmd_install {
    my $self = shift;
    die "Need arguments or cpanfile.\n"
        if !@{$self->{packages}} && !-f $self->{cpanfile};

    my $master = Acme::CPAN::Installer::Master->new(
        inc => [$self->_search_inc],
    );
    my $menlo_base = "$ENV{HOME}/.experimental-installer/work";
    my $menlo_build_log = "$ENV{HOME}/.experimental-installer/build.@{[time]}.log";
    my $cb = sub {
        my ($read_fh, $write_fh) = @_;
        my $worker = Acme::CPAN::Installer::Worker->new(
            verbose => $self->{verbose},
            cpanmetadb => $self->{cpanmetadb},
            mirror => $self->{mirror},
            read_fh => $read_fh, write_fh => $write_fh,
            ($self->{global} ? () : (local_lib => $self->{local_lib})),
            menlo_base => $menlo_base, menlo_build_log => $menlo_build_log,
        );
        $worker->run_loop;
    };

    $master->spawn_worker($cb) for 1 .. $self->{workers};

    if (!@{$self->{packages}} && -f $self->{cpanfile}) {
        warn "Loading modules from $self->{cpanfile}...\n";
        my @packages = grep {
            !$master->is_installed($_->{package}, $_->{version})
        } $self->load_cpanfile($self->{cpanfile});
        do { warn "All requirements are satisfied.\n"; exit } unless @packages;

        if (-f $self->{snapshot}) {
            warn "Loading distributions from $self->{snapshot}...\n";
            my @distributions = grep {
                my $dist = $_;
                grep {$dist->providing($_->{package}, $_->{version})} @packages;
            } $self->load_snapshot($self->{snapshot});
            $master->add_distribution($_) for @distributions;
        } else {
            $self->{packages} = \@packages;
        }
    }

    $master->add_job(
        type => "resolve",
        package => $_->{package},
        version => $_->{version} || 0
    ) for @{$self->{packages}};

    MAIN_LOOP:
    while (1) {
        for my $worker ($master->ready_workers) {
            $master->register_result($worker->result) if $worker->has_result;
            my $job = $master->get_job or last MAIN_LOOP;
            $worker->work($job);
        }
    }
    $master->shutdown_workers;
    my $fail = $master->fail;
    if ($fail) {
        my ($install, $resolve) = @{ $fail }{qw(install resolve)};
        warn "\e[31mFAIL\e[m resolve $_\n" for @$resolve;
        warn "\e[31mFAIL\e[m install $_\n" for @$install;
        return 1;
    } else {
        return 0;
    }
}

sub load_cpanfile {
    my ($self, $file) = @_;
    require Module::CPANfile;
    my $cpanfile = Module::CPANfile->load($file);
    my @package;
    for my $package ($cpanfile->merged_requirements->required_modules) {
        next if $package eq "perl";
        my $version =$cpanfile->prereq_for_module($package)->requirement->version;
        push @package, { package => $package, version => $version };
    }
    @package;
}

sub load_snapshot {
    my ($self, $file) = @_;
    require Carton::Snapshot;
    my $snapshot = Carton::Snapshot->new(path => $file);
    $snapshot->load;
    my @distributions;
    for my $dist ($snapshot->distributions) {
        my @provides = map {
            my $package = $_;
            my $version = $dist->provides->{$_}{version};
            $version = undef if $version eq "undef";
            +{ package => $package, version => $version };
        } sort keys %{$dist->provides};

        push @distributions, Acme::CPAN::Installer::Distribution->new(
            distfile => $dist->distfile,
            provides => \@provides,
        );
    }
    @distributions;
}

1;
__END__

=encoding utf-8

=for stopwords npm

=head1 NAME

Acme::CPAN::Installer - an experimental cpan module installer

=head1 SYNOPSIS

  > cpan-installer install Module1 Module2 ...

  # from cpanfile
  > cpan-installer install

=head1 INSTALL

This module depends on L<Menlo::CLI::Compat|https://github.com/miyagawa/cpanminus/tree/menlo>,
so you have to install it first:

  > cpanm git://github.com/miyagawa/cpanminus.git@menlo

Then install this module:

  > cpanm git://github.com/shoichikaji/Acme-CPAN-Installer.git

=head1 DESCRIPTION

Acme::CPAN::Installer is an experimental cpan module installer,
which uses Menlo::CLI::Compat in parallel.

=head1 MOTIVATION

My motivation is simple: I want to install cpan modules as quickly as possible.

=head1 WHY INSTALLATION OF CPAN MODULES IS SO HARD

I think the hardest part of installation of cpan modules is that
cpan world has two notions B<modules> and B<distributions>,
and cpan clients must handle these correspondence correctly.

I suspect this only applies to cpan world,
and never applies to, for example, ruby gems or node npm.

=head1 AUTHOR

Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2015- Shoichi Kaji

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<App::cpanminus>

L<Carton>

=cut
