package App::cpm;
use 5.008001;
use strict;
use warnings;
use App::cpm::Master;
use App::cpm::Worker;
use App::cpm::Logger;
use App::cpm::version;
use App::cpm::Resolver::MetaDB;
use App::cpm::Resolver::MetaCPAN;
use App::cpm::Resolver::Cascade;
use Parallel::Pipes;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use List::Util ();
use Pod::Usage ();
use File::Spec;
use File::Path ();
use Cwd ();
use Config;

our $VERSION = '0.954';
our $GIT_DESCRIBE;
our $GIT_URL;

use constant WIN32 => $^O eq 'MSWin32';

sub determine_home { # taken from Menlo
    my $class = shift;

    my $homedir = $ENV{HOME}
      || eval { require File::HomeDir; File::HomeDir->my_home }
      || join('', @ENV{qw(HOMEDRIVE HOMEPATH)}); # Win32

    if (WIN32) {
        require Win32; # no fatpack
        $homedir = Win32::GetShortPathName($homedir);
    }

    return "$homedir/.perl-cpm";
}

sub new {
    my ($class, %option) = @_;
    my $prebuilt = exists $ENV{PERL_CPM_PREBUILT} && !$ENV{PERL_CPM_PREBUILT} ? 0 : 1;
    bless {
        home => $class->determine_home,
        workers => WIN32 ? 1 : 5,
        snapshot => "cpanfile.snapshot",
        cpanfile => "cpanfile",
        local_lib => "local",
        cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/",
        mirror => ["https://cpan.metacpan.org/"],
        retry => 1,
        configure_timeout => 60,
        build_timeout => 3600,
        test_timeout => 1800,
        with_requires => 1,
        with_recommends => 0,
        with_suggests => 0,
        with_configure => 0,
        with_build => 1,
        with_test => 1,
        with_runtime => 1,
        with_develop => 0,
        feature => [],
        notest => 1,
        prebuilt => $] >= 5.012 && $prebuilt,
        %option
    }, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @_;
    my (@mirror, @resolver, @feature);
    my $with_option = sub {
        my $n = shift;
        ("with-$n", \$self->{"with_$n"}, "without-$n", sub { $self->{"with_$n"} = 0 });
    };
    GetOptions
        "L|local-lib-contained=s" => \($self->{local_lib}),
        "color!" => \($self->{color}),
        "g|global" => \($self->{global}),
        "mirror=s@" => \@mirror,
        "v|verbose" => \($self->{verbose}),
        "w|workers=i" => \($self->{workers}),
        "target-perl=s" => \my $target_perl,
        "test!" => sub { $self->{notest} = $_[1] ? 0 : 1 },
        "cpanfile=s" => \($self->{cpanfile}),
        "snapshot=s" => \($self->{snapshot}),
        "sudo" => \($self->{sudo}),
        "r|resolver=s@" => \@resolver,
        "mirror-only" => \($self->{mirror_only}),
        "dev" => \($self->{dev}),
        "man-pages" => \($self->{man_pages}),
        "home=s" => \($self->{home}),
        "retry!" => \($self->{retry}),
        "exclude-vendor!" => \($self->{exclude_vendor}),
        "configure-timeout=i" => \($self->{configure_timeout}),
        "build-timeout=i" => \($self->{build_timeout}),
        "test-timeout=i" => \($self->{test_timeout}),
        "show-progress!" => \($self->{show_progress}),
        "prebuilt!" => \($self->{prebuilt}),
        "reinstall" => \($self->{reinstall}),
        (map $with_option->($_), qw(requires recommends suggests)),
        (map $with_option->($_), qw(configure build test runtime develop)),
        "feature=s@" => \@feature,
    or exit 1;

    $self->{local_lib} = $self->maybe_abs($self->{local_lib}) unless $self->{global};
    $self->{home} = $self->maybe_abs($self->{home});
    $self->{resolver} = \@resolver;
    $self->{feature} = \@feature if @feature;
    $self->{mirror} = \@mirror if @mirror;
    for my $mirror (@{$self->{mirror}}) {
        $mirror = $self->normalize_mirror($mirror)
    }
    $self->{color} = 1 if !defined $self->{color} && -t STDOUT;
    $self->{show_progress} = 1 if !WIN32 && !defined $self->{show_progress} && -t STDOUT;
    if ($target_perl) {
        die "--target-perl option conflicts with --global option\n" if $self->{global};
        die "--target-perl option can be used only if perl version >= 5.16.0\n" if $] < 5.016;
        # 5.8 is interpreted as 5.800, fix it
        $target_perl = "v$target_perl" if $target_perl =~ /^5\.[1-9]\d*$/;
        $target_perl = sprintf '%0.6f', App::cpm::version->parse($target_perl)->numify;
        $target_perl = '5.008' if $target_perl eq '5.008000';
        $self->{target_perl} = $target_perl;
    }
    if (WIN32 and $self->{workers} != 1) {
        die "The number of workers must be 1 under WIN32 environment.\n";
    }
    if ($self->{sudo}) {
        !system "sudo", $^X, "-e1" or exit 1;
    }
    if ($self->{sudo} or $self->{man_pages} or $] < 5.012) {
        $self->{prebuilt} = 0;
    }

    $App::cpm::Logger::COLOR = 1 if $self->{color};
    $App::cpm::Logger::VERBOSE = 1 if $self->{verbose};
    $App::cpm::Logger::SHOW_PROGRESS = 1 if $self->{show_progress};

    if (@ARGV && $ARGV[0] eq "-") {
        $self->{argv} = $self->read_argv_from_stdin;
        $self->{cpanfile} = undef;
    } else {
        $self->{argv} = \@ARGV;
    }
}

sub read_argv_from_stdin {
    my $self = shift;
    my @argv;
    while (my $line = <STDIN>) {
        next if $line !~ /\S/;
        next if $line =~ /^\s*#/;
        $line =~ s/^\s*//;
        $line =~ s/\s*$//;
        push @argv, split /\s+/, $line;
    }
    return \@argv;
}

sub _inc {
    my $self = shift;
    return \@INC if $self->{global};

    my $base = $self->{local_lib};
    require local::lib;
    my @local_lib = (
        local::lib->resolve_path(local::lib->install_base_arch_path($base)),
        local::lib->resolve_path(local::lib->install_base_perl_path($base)),
    );
    my @core = (
        (!$self->{exclude_vendor} ? grep {$_} @Config{qw(vendorarch vendorlibexp)} : ()),
        @Config{qw(archlibexp privlibexp)},
    );
    if ($self->{target_perl}) {
        return [@local_lib];
    } else {
        return [@local_lib, @core];
    }
}

sub maybe_abs {
    my ($self, $path) = @_;
    if (File::Spec->file_name_is_absolute($path)) {
        return $path;
    } else {
        File::Spec->canonpath(File::Spec->catdir(Cwd::cwd(), $path));
    }
}

sub normalize_mirror {
    my ($self, $mirror) = @_;
    $mirror =~ s{/*$}{/};
    return $mirror if $mirror =~ m{^https?://};
    $mirror =~ s{^file://}{};
    die "$mirror: No such directory.\n" unless -d $mirror;
    "file://" . $self->maybe_abs($mirror);
}

sub run {
    my ($self, @argv) = @_;
    my $cmd = shift @argv or die "Need subcommand, try `cpm --help`\n";
    $cmd = "help"    if $cmd =~ /^(-h|--help)$/;
    $cmd = "version" if $cmd =~ /^(-V|--version)$/;
    if (my $sub = $self->can("cmd_$cmd")) {
        return $self->$sub(@argv) if $cmd eq "exec";
        $self->parse_options(@argv);
        return $self->$sub;
    } else {
        my $message = $cmd =~ /^-/ ? "Missing subcommand" : "Unknown subcommand '$cmd'";
        die "$message, try `cpm --help`\n";
    }
}

sub cmd_help {
    Pod::Usage::pod2usage(0);
}

sub cmd_version {
    print "cpm $VERSION ($0)\n";
    if ($GIT_DESCRIBE && $GIT_URL) {
        print "This is a self-contained version, $GIT_DESCRIBE ($GIT_URL)\n";
    }
    return 0;
}

sub cmd_install {
    my $self = shift;
    die "Need arguments or cpanfile.\n"
        if !@{$self->{argv}} && (!$self->{cpanfile} || !-f $self->{cpanfile});

    File::Path::mkpath($self->{home}) unless -d $self->{home};
    my $logger = App::cpm::Logger::File->new("$self->{home}/build.log.@{[time]}");
    $logger->symlink_to("$self->{home}/build.log");
    $logger->log("Running cpm $VERSION ($0) on perl $Config{version} built for $Config{archname} ($^X)");
    $logger->log("This is a self-contained version, $GIT_DESCRIBE ($GIT_URL)") if $GIT_DESCRIBE && $GIT_URL;
    $logger->log("Command line arguments are: @ARGV");

    my $master = App::cpm::Master->new(
        logger => $logger,
        inc    => $self->_inc,
        show_progress => $self->{show_progress},
        (exists $self->{target_perl} ? (target_perl => $self->{target_perl}) : ()),
    );

    my ($packages, $dists) = $self->initial_job($master);
    return 0 unless $packages;

    my $worker = App::cpm::Worker->new(
        verbose   => $self->{verbose},
        home      => $self->{home},
        logger    => $logger,
        notest    => $self->{notest},
        sudo      => $self->{sudo},
        resolver  => $self->generate_resolver,
        man_pages => $self->{man_pages},
        retry     => $self->{retry},
        prebuilt  => $self->{prebuilt},
        configure_timeout => $self->{configure_timeout},
        build_timeout     => $self->{build_timeout},
        test_timeout      => $self->{test_timeout},
        ($self->{global} ? () : (local_lib => $self->{local_lib})),
    );

    if ($] < 5.016) {
        my %toolchain = ('ExtUtils::MakeMaker' => '6.58', 'ExtUtils::ParseXS' => '3.16');
        for my $name (sort keys %toolchain) {
            my ($req, $i);
            my $req_range = $toolchain{$name};
            if ( ($i) = grep { $packages->[$_]{package} eq $name } 0..$#{$packages} ) {
                my $user = $packages->[$i];
                my $range = eval { App::cpm::version::range_merge($user->{version_range}, $req_range) };
                die sprintf "We have to install %s %s or later first, but you requested that of %s\n",
                    $name, $req_range, $user->{version_range} if $@;
                $req = { package => $name, version_range => $range, dev => $user->{dev} };
                splice @$packages, $i, 1 if defined $i;
            } else {
                $req = { package => $name, version_range => $req_range };
            }
            my ($is_satisfied, @need_resolve) = $master->is_satisfied([$req]);
            if (!$is_satisfied) {
                $master->add_job(type => "resolve", %$_) for @need_resolve;
            }
        }

        $self->install($master, $worker, 1);
        if (my $fail = $master->fail) {
            local $App::cpm::Logger::VERBOSE = 0;
            for my $type (qw(install resolve)) {
                App::cpm::Logger->log(result => "FAIL", type => $type, message => $_) for @{$fail->{$type}};
            }
            print STDERR "\r" if $self->{show_progress};
            warn sprintf "%d distribution%s installed.\n",
                $master->installed_distributions, $master->installed_distributions > 1 ? "s" : "";
            warn "See $self->{home}/build.log for details.\n";
            return 1;
        }
    }

    $master->add_job(type => "resolve", %$_) for @$packages;
    $master->add_distribution($_) for @$dists;
    $self->install($master, $worker, $self->{workers});
    my $fail = $master->fail;
    if ($fail) {
        local $App::cpm::Logger::VERBOSE = 0;
        for my $type (qw(install resolve)) {
            App::cpm::Logger->log(result => "FAIL", type => $type, message => $_) for @{$fail->{$type}};
        }
    }
    print STDERR "\r" if $self->{show_progress};
    warn sprintf "%d distribution%s installed.\n",
        $master->installed_distributions, $master->installed_distributions > 1 ? "s" : "";
    $self->cleanup;

    if ($fail) {
        warn "See $self->{home}/build.log for details.\n";
        return 1;
    } else {
        return 0;
    }
}

sub install {
    my ($self, $master, $worker, $num) = @_;

    my $pipes = Parallel::Pipes->new($num, sub {
        my $job = shift;
        return $worker->work($job);
    });
    my $get_job; $get_job = sub {
        my $master = shift;
        if (my @job = $master->get_job) {
            return @job;
        }
        if (my @written = $pipes->is_written) {
            my @ready = $pipes->is_ready(@written);
            $master->register_result($_->read) for @ready;
            return $master->$get_job;
        } else {
            return;
        }
    };
    while (my @job = $master->$get_job) {
        my @ready = $pipes->is_ready;
        $master->register_result($_->read) for grep $_->is_written, @ready;
        for my $i (0 .. List::Util::min($#job, $#ready)) {
            $job[$i]->in_charge(1);
            $ready[$i]->write($job[$i]);
        }
    }
    $pipes->close;
}

sub cleanup {
    my $self = shift;
    my $week = time - 7*24*60*60;
    my @entry = glob "$self->{home}/build.log.*";
    if (opendir my $dh, "$self->{home}/work") {
        push @entry,
            map File::Spec->catdir("$self->{home}/work", $_),
            grep !/^\.{1,2}$/,
            readdir $dh;
    }
    for my $entry (@entry) {
        my $mtime = (stat $entry)[9];
        if ($mtime < $week) {
            if (-d $entry) {
                File::Path::rmtree($entry);
            } else {
                unlink $entry;
            }
        }
    }
}

sub initial_job {
    my ($self, $master) = @_;

    my (@package, @dist);
    for (@{$self->{argv}}) {
        my $arg = $_; # copy
        my ($package, $dist);
        if (-d $arg || -f $arg || $arg =~ s{^file://}{}) {
            $arg = $self->maybe_abs($arg);
            $dist = App::cpm::Distribution->new(source => "local", uri => "file://$arg", provides => []);
        } elsif ($arg =~ /(?:^git:|\.git(?:@.+)?$)/) {
            my %ref = $arg =~ s/(?<=\.git)@(.+)$// ? (ref => $1) : ();
            $dist = App::cpm::Distribution->new(source => "git", uri => $arg, provides => [], %ref);
        } elsif ($arg =~ m{^https?://}) {
            my ($source, $distfile) = ("http", undef);
            if ($arg =~ m{^https?://(?:www.cpan.org|backpan.perl.org|cpan.metacpan.org)/authors/id/(.+)}) {
                ($source, $distfile) = ("cpan", $1);
            }
            $dist = App::cpm::Distribution->new(
                source => $source,
                uri => $arg,
                $distfile ? (distfile => $distfile) : (),
                provides => [],
            );
        } elsif ($arg =~ m!^(?:[A-Z]/[A-Z]{2}/)?([A-Z]{2}[\-A-Z0-9]*/.*)$!) {
            my $distfile = $1;
            $distfile =~ m{^((.).)};
            $distfile = "$2/$1/$distfile";
            $dist = App::cpm::Distribution->new(
                source => "cpan",
                uri => [map { "${_}authors/id/$distfile" } @{$self->{mirror}}],
                distfile => $distfile,
                provides => [],
            );
        } else {
            my ($name, $version_range, $dev);
            # copy from Menlo
            # Plack@1.2 -> Plack~"==1.2"
            $arg =~ s/^([A-Za-z0-9_:]+)@([v\d\._]+)$/$1~== $2/;
            # support Plack~1.20, DBI~"> 1.0, <= 2.0"
            if ($arg =~ /\~[v\d\._,\!<>= ]+$/) {
                ($name, $version_range) = split '~', $arg, 2;
            } else {
                $arg =~ s/[~@]dev$// and $dev++;
                $name = $arg;
            }
            $package = +{
                package => $name,
                version_range => $version_range || 0,
                dev => $dev,
                reinstall => $self->{reinstall},
            };
        }
        push @package, $package if $package;
        push @dist, $dist if $dist;
    }

    if (!@{$self->{argv}}) {
        my ($requirements, $dists) = $self->load_cpanfile($self->{cpanfile});
        push @dist, @$dists;
        my ($is_satisfied, @need_resolve) = $master->is_satisfied($requirements);
        if (!@$dists and $is_satisfied) {
            warn "All requirements are satisfied.\n";
            return;
        } elsif (!defined $is_satisfied) {
            my ($req) = grep { $_->{package} eq "perl" } @$requirements;
            die sprintf "%s requires perl %s, but you have only %s\n",
                $self->{cpanfile}, $req->{version_range}, $self->{target_perl} || $];
        } else {
            push @package, @need_resolve;
        }
    }

    return (\@package, \@dist);
}

sub load_cpanfile {
    my ($self, $file) = @_;
    require Module::CPANfile;
    my $cpanfile = Module::CPANfile->load($file);
    my $prereqs = $cpanfile->prereqs_with(@{ $self->{"feature"} });
    my @phase = grep $self->{"with_$_"}, qw(configure build test runtime develop);
    my @type  = grep $self->{"with_$_"}, qw(requires recommends suggests);
    my $requirements = $prereqs->merged_requirements(\@phase, \@type);
    my $hash = $requirements->as_string_hash;

    my (@package, @distribution);
    for my $package (sort keys %$hash) {
        my $option = $cpanfile->options_for_module($package) || +{};
        my $uri;
        if ($uri = $option->{git}) {
            push @distribution, App::cpm::Distribution->new(
                source => "git", uri => $uri, ref => $option->{ref},
                provides => [{package => $package}],
            );
        } elsif ($uri = $option->{dist}) {
            my $source = $uri =~ m{^file://} ? "local" : "http";
            push @distribution, App::cpm::Distribution->new(
                source => $source, uri => $uri,
                provides => [{package => $package}],
            );
        } else {
            push @package, {
                package => $package, version_range => $hash->{$package}, dev => $option->{dev},
            };
        }
    }
    (\@package, \@distribution);
}

sub generate_resolver {
    my $self = shift;

    my $cascade = App::cpm::Resolver::Cascade->new;
    if (@{$self->{resolver}}) {
        for (@{$self->{resolver}}) {
            my ($klass, @arg) = split /,/, $_;
            my $resolver;
            if ($klass =~ /^metadb$/i) {
                $resolver = App::cpm::Resolver::MetaDB->new(
                    mirror => @arg ? [map $self->normalize_mirror($_), @arg] : $self->{mirror}
                );
            } elsif ($klass =~ /^metacpan$/i) {
                $resolver = App::cpm::Resolver::MetaCPAN->new(dev => $self->{dev});
            } elsif ($klass =~ /^02packages?$/i) {
                require App::cpm::Resolver::02Packages;
                my ($path, $mirror);
                if (@arg > 1) {
                    ($path, $mirror) = @arg;
                } elsif (@arg == 1) {
                    $mirror = $arg[0];
                } else {
                    $mirror = $self->{mirror}[0];
                }
                $resolver = App::cpm::Resolver::02Packages->new(
                    $path ? (path => $path) : (),
                    cache => "$self->{home}/sources",
                    mirror => $self->normalize_mirror($mirror),
                );
            } elsif ($klass =~ /^snapshot$/i) {
                require App::cpm::Resolver::Snapshot;
                $resolver = App::cpm::Resolver::Snapshot->new(
                    path => $self->{snapshot},
                    mirror => @arg ? [map $self->normalize_mirror($_), @arg] : $self->{mirror},
                );
            } else {
                die "Unknown resolver: $klass\n";
            }
            $cascade->add($resolver);
        }
        return $cascade;
    }

    if ($self->{mirror_only}) {
        require App::cpm::Resolver::02Packages;
        for my $mirror (@{$self->{mirror}}) {
            my $resolver = App::cpm::Resolver::02Packages->new(
                mirror => $mirror,
                cache => "$self->{home}/sources",
            );
            $cascade->add($resolver);
        }
        return $cascade;
    }

    if (!@{$self->{argv}} and -f $self->{snapshot}) {
        if (!eval { require App::cpm::Resolver::Snapshot }) {
            die "To load $self->{snapshot}, you need to install Carton::Snapshot.\n";
        }
        warn "Loading distributions from $self->{snapshot}...\n";
        my $resolver = App::cpm::Resolver::Snapshot->new(
            path => $self->{snapshot},
            mirror => $self->{mirror},
        );
        $cascade->add($resolver);
    }

    my $resolver = App::cpm::Resolver::MetaCPAN->new(
        $self->{dev} ? (dev => 1) : (only_dev => 1)
    );
    $cascade->add($resolver);
    $resolver = App::cpm::Resolver::MetaDB->new(
        uri => $self->{cpanmetadb},
        mirror => $self->{mirror},
    );
    $cascade->add($resolver);
    if (!$self->{dev}) {
        $resolver = App::cpm::Resolver::MetaCPAN->new;
        $cascade->add($resolver);
    }

    $cascade;
}

1;
__END__

=encoding utf-8

=head1 NAME

App::cpm - a fast CPAN module installer

=head1 SYNOPSIS

  > cpm install Module

=head1 DESCRIPTION

=for html
<a href="https://raw.githubusercontent.com/skaji/cpm/master/xt/demo.gif"><img src="https://raw.githubusercontent.com/skaji/cpm/master/xt/demo.gif" alt="demo" style="max-width:100%;"></a>

cpm is a fast CPAN module installer, which uses L<Menlo> in parallel.

Moreover cpm keeps the each builds of distributions in your home directory,
and reuses them later.
That is, if prebuilts are available, cpm never builds distributions again, just copies the prebuilts into an appropriate directory.
This is (of course!) inspired by L<Carmel>.

For tutorial, check out L<App::cpm::Tutorial>.

=head1 MOTIVATION

Why do we need a new CPAN client?

I used L<cpanm> a lot, and it's totally awesome.

But if your Perl project has hundreds of CPAN module dependencies,
then it takes quite a lot of time to install them.

So my motivation is simple: I want to install CPAN modules as fast as possible.

=head2 HOW FAST?

Just an example:

  > time cpanm -nq -Lextlib Plack
  real 0m47.705s

  > time cpm install Plack
  real 0m16.629s

This shows cpm is 3x faster than cpanm.

=head1 CAVEATS

L<eserte|https://github.com/skaji/cpm/issues/71> reported that
the parallel feature of cpm yielded a new type of failure for CPAN module installation.
That is,
if B<ModuleA> implicitly requires B<ModuleB> in configure/build phase,
and B<ModuleB> is about to be installed,
then it may happen that the installation of B<ModuleA> fails.

I can say that it hardly happens especially if you use a new Perl.
Moreover, for a workaround, cpm automatically retries the installation if it fails.

I hope that
if almost all CPAN modules are distributed with L<static install enabled|http://blogs.perl.org/users/shoichi_kaji1/2017/03/make-your-cpan-module-static-installable.html>,
then cpm will parallelize the installation for these CPAN modules safely and we can eliminate this new type of failure completely.

=head1 ROADMAP

If you all find cpm useful,
then cpm should be merged into cpanm 2.0. How exciting!

To merge cpm into cpanm, there are several TODOs:

=over 4

=item * (DONE) Win32? - support platforms that do not have fork(2) system call

=item * (DONE) Logging? - the parallel feature makes log really messy

=back

Your feedback is highly appreciated.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 COMMUNITY

=over 4

=item L<https://github.com/skaji/cpm>

Code repository and issue tracker

=item L<https://gitter.im/skaji/cpm>

Chat room. I would like to hear your thoughts about CPAN clients (not necessary about cpm)

=back

=head1 SEE ALSO

L<Perl Advent Calendar 2015|http://www.perladvent.org/2015/2015-12-02.html>

L<App::cpanminus>

L<Menlo>

L<Carton>

L<Carmel>

=cut
