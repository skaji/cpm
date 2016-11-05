package App::cpm;
use 5.008_005;
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
use Cwd 'abs_path';
use Config;

our $VERSION = '0.213';

use constant WIN32 => $^O eq 'MSWin32';

sub new {
    my ($class, %option) = @_;
    bless {
        home => "$ENV{HOME}/.perl-cpm",
        workers => WIN32 ? 1 : 5,
        snapshot => "cpanfile.snapshot",
        cpanfile => "cpanfile",
        local_lib => "local",
        cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/",
        mirror => ["http://www.cpan.org/", "http://backpan.perl.org/"],
        target_perl => $],
        %option
    }, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @_;
    $self->{notest} = 1;
    my (@mirror, @resolver);
    GetOptions
        "L|local-lib-contained=s" => \($self->{local_lib}),
        "V|version" => sub { $self->cmd_version },
        "color!" => \($self->{color}),
        "g|global" => \($self->{global}),
        "h|help" => sub { $self->cmd_help },
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
    or exit 1;

    $self->{local_lib} = abs_path $self->{local_lib} unless $self->{global};
    $self->{resolver} = \@resolver;
    $self->{mirror} = \@mirror if @mirror;
    for my $mirror (@{$self->{mirror}}) {
        $mirror =~ s{/*$}{/};
        $mirror = "file://$mirror" if $mirror !~ m{^https?://} and -d $mirror;
    }
    $self->{color} = 1 if !defined $self->{color} && -t STDOUT;
    if ($target_perl) {
        # 5.8 is interpreted as 5.800, fix it
        $target_perl = "v$target_perl" if $target_perl =~ /^5\.[1-9]\d*$/;
        $self->{target_perl} = App::cpm::version->parse($target_perl)->numify;
        if ($self->{target_perl} > $]) {
            die "--target-perl must be lower than your perl version $]\n";
        }
    }
    if (WIN32 and $self->{workers} != 1) {
        die "The number of workers must be 1 under WIN32 environment.\n";
    }
    if ($self->{sudo}) {
        !system "sudo", $^X, "-e1" or exit 1;
    }

    $App::cpm::Logger::COLOR = 1 if $self->{color};
    $App::cpm::Logger::VERBOSE = 1 if $self->{verbose};
    $self->{argv} = \@ARGV;
}

sub _core_inc {
    my $self = shift;
    (
        (!$self->{exclude_vendor} ? grep {$_} @Config{qw(vendorarch vendorlibexp)} : ()),
        @Config{qw(archlibexp privlibexp)},
    );
}

sub _user_inc {
    my $self = shift;
    if ($self->{global}) {
        my %core = map { $_ => 1 } $self->_core_inc;
        return grep { !$core{$_} } @INC;
    }

    my $base = $self->{local_lib};
    require local::lib;
    (
        local::lib->resolve_path(local::lib->install_base_arch_path($base)),
        local::lib->resolve_path(local::lib->install_base_perl_path($base)),
    );
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
    die "Need arguments or cpanfile.\n" if !@{$self->{argv}} && !-f $self->{cpanfile};

    my $master = App::cpm::Master->new(
        core_inc => [$self->_core_inc],
        user_inc => [$self->_user_inc],
        target_perl => $self->{target_perl},
    );
    $self->register_initial_job($master);

    my $worker = App::cpm::Worker->new(
        verbose         => $self->{verbose},
        cache           => "$self->{home}/cache",
        menlo_base      => "$self->{home}/work",
        menlo_build_log => "$self->{home}/build.@{[time]}.log",
        notest          => $self->{notest},
        sudo            => $self->{sudo},
        resolver        => $self->generate_resolver,
        man_pages       => $self->{man_pages},
        ($self->{global} ? () : (local_lib => $self->{local_lib})),
    );
    my $pipes = Parallel::Pipes->new($self->{workers}, sub {
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

    if (my $fail = $master->fail) {
        local $App::cpm::Logger::VERBOSE = 0;
        for my $type (qw(install resolve)) {
            App::cpm::Logger->log(
                result => "FAIL",
                type => $type,
                message => $_,
            ) for @{$fail->{$type}};
        }
    }
    my $num = $master->installed_distributions;
    warn "$num distribution@{[$num > 1 ? 's' : '']} installed.\n";
    $self->cleanup;
    return $master->fail ? 1 : 0;
}

sub cleanup {
    my $self = shift;
    my $week = time - 7*24*60*60;
    my @file = map  { $_->[0] }
               grep { $_->[1] < $week }
               map  { [$_, (stat $_)[9]] }
               glob "$self->{home}/build*.log";
    unlink $_ for @file;
}

sub register_initial_job {
    my ($self, $master) = @_;

    my @package;
    for my $arg (@{$self->{argv}}) {
        if (-d $arg || -f $arg) {
            $arg = abs_path $arg;
            my $dist = App::cpm::Distribution->new(source => "local", uri => "file://$arg", provides => []);
            $master->add_distribution($dist);
        } elsif ($arg =~ /(?:^git:|\.git(?:@.+)?$)/) {
            my %ref = $arg =~ s/(?<=\.git)@(.+)$// ? (ref => $1) : ();
            my $dist = App::cpm::Distribution->new(source => "git", uri => $arg, provides => [], %ref);
            $master->add_distribution($dist);
        } elsif ($arg =~ m{^https?://}) {
            my $dist = App::cpm::Distribution->new(source => "http", uri => $arg, provides => []);
            $master->add_distribution($dist);
        } else {
            my ($package, $version, $dev);
            # copy from Menlo
            # Plack@1.2 -> Plack~"==1.2"
            $arg =~ s/^([A-Za-z0-9_:]+)@([v\d\._]+)$/$1~== $2/;
            # support Plack~1.20, DBI~"> 1.0, <= 2.0"
            if ($arg =~ /\~[v\d\._,\!<>= ]+$/) {
                ($package, $version) = split '~', $arg, 2;
            } else {
                $arg =~ s/[~@]dev$// and $dev++;
                $package = $arg;
            }
            push @package, {package => $package, version => $version || 0, dev => $dev};
        }
    }

    if (!@{$self->{argv}}) {
        my ($requirements, $dist) = $self->load_cpanfile($self->{cpanfile});
        $master->add_distribution($_) for @$dist;
        my ($is_satisfied, @need_resolve) = $master->is_satisfied($requirements);
        if (!@$dist and $is_satisfied) {
            warn "All requirements are satisfied.\n";
            exit 0;
        } elsif (!defined $is_satisfied) {
            my ($req) = grep { $_->{package} eq "perl" } @$requirements;
            die sprintf "%s requires perl %s\n", $self->{cpanfile}, $req->{version};
        } else {
            @package = @need_resolve;
        }
    }

    for my $p (@package) {
        $master->add_job(
            type => "resolve",
            package => $p->{package},
            version => $p->{version} || 0,
            dev => $p->{dev},
        );
    }
}

sub load_cpanfile {
    my ($self, $file) = @_;
    require Module::CPANfile;
    my $cpanfile = Module::CPANfile->load($file);
    my $prereqs = $cpanfile->prereqs_with;
    my $phases = [qw(build test runtime)];
    my $requirements = $prereqs->merged_requirements($phases, ['requires']);
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
                package => $package, version => $hash->{$package}, dev => $option->{dev},
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
                    mirror => @arg ? \@arg : $self->{mirror}
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
                    mirror => $mirror,
                );
            } elsif ($klass =~ /^snapshot$/i) {
                require App::cpm::Resolver::Snapshot;
                $resolver = App::cpm::Resolver::Snapshot->new(
                    path => $self->{snapshot},
                    mirror => @arg ? \@arg : $self->{mirror},
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

B<THIS IS EXPERIMENTAL.>

cpm is a fast CPAN module installer, which uses L<Menlo> in parallel.
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

=head1 ROADMAP

If you all find cpm useful,
then cpm should be merged into cpanm 2.0. How exciting!

To merge cpm into cpanm, there are several TODOs:

=over 4

=item * (DONE) Win32? - support platforms that do not have fork(2) system call

=item * Logging? - the parallel feature makes log really messy

=back

Your feedback is highly appreciated.

=head1 COPYRIGHT AND LICENSE

Copyright 2015 Shoichi Kaji E<lt>skaji@cpan.orgE<gt>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO


L<Perl Advent Calendar 2015|http://www.perladvent.org/2015/2015-12-02.html>

L<App::cpanminus>

L<Menlo>

L<Carton>

=cut
