package App::cpm;
use 5.008_005;
use strict;
use warnings;
use App::cpm::Master;
use App::cpm::Worker;
use App::cpm::Logger;
use App::cpm::version;
use App::cpm::Resolver::MetaDB;
use App::cpm::Resolver::Multiplexer;
use Parallel::Pipes;
use Getopt::Long qw(:config no_auto_abbrev no_ignore_case bundling);
use List::Util ();
use Pod::Usage ();
use Cwd 'abs_path';
use Config;

our $VERSION = '0.118';

use constant WIN32 => $^O eq 'MSWin32';

sub new {
    my ($class, %option) = @_;
    bless {
        workers => WIN32 ? 1 : 5,
        snapshot => "cpanfile.snapshot",
        cpanfile => "cpanfile",
        local_lib => "local",
        cpanmetadb => "http://cpanmetadb.plackperl.org/v1.0/package",
        mirror => ["http://www.cpan.org", "http://backpan.perl.org"],
        target_perl => $],
        %option
    }, $class;
}

sub parse_options {
    my $self = shift;
    local @ARGV = @_;
    $self->{notest} = 1;
    my @mirror;
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
    or exit 1;

    $self->{local_lib} = abs_path $self->{local_lib} unless $self->{global};
    $self->{mirror} = \@mirror if @mirror;
    $_ =~ s{/$}{} for @{$self->{mirror}};
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
    @ARGV;
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
        @argv = $self->parse_options(@argv) unless $cmd eq "exec";
        return $self->$sub(@argv);
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
    my ($self, @argv) = @_;
    die "Need arguments or cpanfile.\n" if !@argv && !-f $self->{cpanfile};

    my $master = App::cpm::Master->new(
        core_inc => [$self->_core_inc],
        user_inc => [$self->_user_inc],
        target_perl => $self->{target_perl},
    );
    $self->register_initial_job($master => @argv);

    my $resolver = App::cpm::Resolver::Multiplexer->new;
    if (!@argv && -f $self->{snapshot}) {
        if (!eval { require App::cpm::Resolver::Snapshot }) {
            die "To load $self->{snapshot}, you need to install Carton::Snapshot.\n";
        }
        warn "Loading distributions from $self->{snapshot}...\n";
        $resolver->append(App::cpm::Resolver::Snapshot->new(snapshot => $self->{snapshot}));
    }
    $resolver->append(App::cpm::Resolver::MetaDB->new(cpanmetadb => $self->{cpanmetadb}));

    my $worker = App::cpm::Worker->new(
        verbose         => $self->{verbose},
        mirror          => $self->{mirror},
        menlo_base      => "$ENV{HOME}/.perl-cpm/work",
        menlo_cache     => "$ENV{HOME}/.perl-cpm/cache",
        menlo_build_log => "$ENV{HOME}/.perl-cpm/build.@{[time]}.log",
        notest          => $self->{notest},
        sudo            => $self->{sudo},
        resolver        => $resolver,
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
    return $master->fail ? 1 : 0;
}

sub register_initial_job {
    my ($self, $master, @argv) = @_;

    my @package;
    for my $arg (@argv) {
        if (-d $arg or $arg =~ /(?:^git:|\.git(?:@.+)?$)/) {
            $arg = abs_path $arg if -d $arg;
            my $dist = App::cpm::Distribution->new(distfile => $arg, provides => []);
            $master->add_distribution($dist);
        } else {
            push @package, {package => $arg, version => 0};
        }
    }

    if (!@argv) {
        warn "Loading modules from $self->{cpanfile}...\n";
        my $requirements = $self->load_cpanfile($self->{cpanfile});
        my ($is_satisfied, @need_resolve) = $master->is_satisfied($requirements);
        if ($is_satisfied) {
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
            version => $p->{version} || 0
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
    [ map { +{ package => $_, version => $hash->{$_} } } keys %$hash ];
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

=item * Win32? - support platforms that do not have fork(2) system call

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
