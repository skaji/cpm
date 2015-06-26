package Acme::CPAN::Installer;

use strict;
use warnings;
use 5.008_005;
our $VERSION = '0.01';

use Acme::CPAN::Installer::Job;
use Acme::CPAN::Installer::Master;
use Acme::CPAN::Installer::Worker;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use Pod::Usage 'pod2usage';
use Cwd 'abs_path';

sub new {
    my ($class, %option) = @_;
    bless {
        workers => 5,
        snapshot => "cpanfile.snapshot",
        cpanfile => "cpanfile",
        %option
    }, $class;
}

sub parse_options {
    my ($self, @argv) = @_;
    local @ARGV = @argv;
    GetOptions
        "L|l|local-lib=s" => \($self->{local_lib} = "local"),
        "w|workers=i" => \($self->{workers} = 5),
        "h|help" => sub { pod2usage(0) },
        "v|version" => sub { printf "%s %s\n", __PACKAGE__, __PACKAGE__->VERSION; exit },
    or exit 1;
    $self->{local_lib} = abs_path $self->{local_lib};
    $self->{packages} = [ map +{ package => $_, version => 0 }, @ARGV ];
    $self;
}

sub run {
    my $self = shift;
    my $master = Acme::CPAN::Installer::Master->new;
    my $menlo_base = "$ENV{HOME}/.experimental-installer";
    my $menlo_build_log = "$menlo_base/build.@{[time]}.log";
    my $cb = sub {
        my ($read_fh, $write_fh) = @_;
        my $worker = Acme::CPAN::Installer::Worker->new(
            read_fh => $read_fh, write_fh => $write_fh,
            local_lib => $self->{local_lib},
            menlo_base => $menlo_base, menlo_build_log => $menlo_build_log,
        );
        $worker->run_loop;
    };

    $master->spawn_worker($cb) for 1 .. $self->{workers};

    my @packages = @{$self->{packages}};
    if (!@packages && -f $self->{snapshot}) {
        my $file = $self->{snapshot};
        warn "Loading distributions from $file...\n";
        my @distributions = $self->load_snapshot($file);
        $master->add_distribution($_) for @distributions;
    } else {
        if (!@packages) {
            my $file = $self->{cpanfile};
            die "Missing both $file and $self->{snapshot}, try: $0 --help\n" unless -f $file;
            warn "Loading modules from $file...\n";
            @packages = $self->load_cpanfile($file);
        }
        $master->add_job(
            type => "resolve",
            package => $_->{package},
            version => $_->{version} || 0
        ) for @packages;
    }

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
        my $hash = $dist->requirements->as_string_hash;
        my @requirements = map {
            +{
                package => $_,
                version => $hash->{version},
                # XXX: cpanfile.snapshot drops phase/type information, so this is dummy
                phase => "runtime",
                type => "requires",
            };
        } sort keys %$hash;

        push @distributions, Acme::CPAN::Installer::Distribution->new(
            distfile => $dist->distfile,
            provides => \@provides,
            requirements => \@requirements,
        );
    }
    @distributions;
}

1;
__END__

=encoding utf-8

=head1 NAME

Acme::CPAN::Installer - an experimental cpan module installer

=head1 SYNOPSIS

Install distributions listed in C<cpanfile.snapshot>:

  # from cpanfile.snapshot
  > cpan-installer

Install modules specified in C<cpanfile> or arguments (very experimental):

  # from cpanfile
  > cpan-installer

  # or explicitly
  > cpan-installer Module1 Module2 ...

=head1 INSTALL

This module depends on L<Menlo::CLI::Compat|https://github.com/miyagawa/cpanminus/tree/menlo>,
so you have to install it first:

  > cpanm git://github.com/miyagawa/cpanminus.git@menlo

Then install this module:

  > cpanm git://github.com/shoichikaji/Acme-CPAN-Installer.git

=head1 DESCRIPTION

Acme::CPAN::Installer is an experimental cpan module installer.

=head1 MOTIVATION

My motivation is simple: I want to install cpan modules as quickly as possible.

=head1 WHY INSTALLATION OF CPAN MODULES IS SO HARD

I think the hardest part of installation of cpan modules is that
cpan world has two notions B<modules> and B<distributions>,
and cpan clients must handle these correspondence correctly.

I suspect this only applies to cpan world,
and never applies to, for example, ruby gems or node npm.

And, the 2nd hardest part is that
we cannot determine the real dependencies of a distribution
unless we fetch it, extract it, execute C<Makefile.PL>/C<Build.PL>, and get C<MYMETA.json>.

So I propose:

=over 4

=item *

Create an API server which offers:

  input:
    * module and its version requirement
  output:
    * distfile path
    * providing modules (modules and versions)
    * dependencies of modules (or distributions?)

I guess this is accomplished by combining
L<http://cpanmetadb.plackperl.org/> and L<https://api.metacpan.org/>.

Sample: L<https://cpanmetadb-provides.herokuapp.com/>

=item *

Forbid cpan distributions to configure themselves dynamically
so that the dependencies are determined statically.

=back

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
