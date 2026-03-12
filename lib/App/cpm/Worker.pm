package App::cpm::Worker;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::Util;
use App::cpm::Worker::Installer;
use App::cpm::Worker::Resolver;
use Config;
use File::Path ();
use File::Spec;
use Time::HiRes qw(gettimeofday tv_interval);

sub new ($class, $ctx, %option) {
    my $home = $option{home};
    my $prebuilt_base;
    if ($option{prebuilt}) {
        $prebuilt_base = $class->prebuilt_base($home);
        File::Path::mkpath($prebuilt_base) if !-d $prebuilt_base;
        my $file = "$prebuilt_base/version";
        if (!-f $file) {
            open my $fh, ">", $file or die "$file: $!";
            print {$fh} "$Config{perlpath}\n";
        }
    }
    %option = (
        %option,
        $prebuilt_base ? (prebuilt_base => $prebuilt_base) : (),
    );
    my $installer = App::cpm::Worker::Installer->new($ctx, %option);
    my $resolver  = App::cpm::Worker::Resolver->new($ctx, %option, impl => $option{resolver});
    bless { %option, installer => $installer, resolver => $resolver }, $class;
}

sub prebuilt_base ($class, $home) {
    my $identity = App::cpm::Util::perl_identity;
    File::Spec->catdir($home, "builds", $identity);
}

sub work ($self, $ctx, $task) {
    my $type = $task->{type} || "(undef)";
    my $result;
    my $start = $self->{verbose} ? [gettimeofday] : undef;
    if (grep {$type eq $_} qw(fetch configure install)) {
        $result = eval { $self->{installer}->work($ctx, $task) };
        warn $@ if $@;
    } elsif ($type eq "resolve") {
        $result = eval { $self->{resolver}->work($ctx, $task) };
        warn $@ if $@;
    } else {
        die "Unknown type: $type\n";
    }
    my $elapsed = $start ? tv_interval($start) : undef;
    $result ||= { ok => 0 };
    $task->merge({%$result, pid => $$, elapsed => $elapsed});
    return $task;
}

1;
