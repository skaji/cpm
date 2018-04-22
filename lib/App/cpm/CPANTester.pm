package App::cpm::CPANTester;
use strict;
use warnings;

use English '-no_match_vars';
use JSON::PP ();
use Module::Metadata;
use Text::SimpleKeyValue::Writer;
use Text::SimpleKeyValue::Reader;

my $JSON = JSON::PP->new->canonical(1)->pretty(1);

sub new {
    my ($class, %args) = @_;
    my $writer = Text::SimpleKeyValue::Writer->new(%args);
    bless {
        perl => $^X,
        key => "",
        writer => $writer,
        inc => \@INC,
        module => {},
        context => '',
        _ref_key => {},
        %args,
    }, $class;
}

sub symlink_to {
    my ($self, %args) = @_;
    for my $key (sort keys %args) {
        my $target = $args{$key};
        unlink $target;
        symlink $self->{$key}, $target;
    }
}

sub write_header {
    my $self = shift;
    $self->write( "perl_V" => scalar `$self->{perl} -V` );
    $self->write( "environment_variables" => $self->environment_variables );
    $self->write( "special_variables" => $self->special_variables );
}

sub local_module {
    my ($self, $module) = @_;
    my $info = Module::Metadata->new_from_module($module, inc => $self->{inc});
    return unless $info;
    +{
        version => $info->version->stringify,
        filename => $info->filename,
    };
}

sub toolchain_versions {
    my $self = shift;
    my @want = qw(
        CPAN
        CPAN::Meta
        Cwd
        ExtUtils::CBuilder
        ExtUtils::Command
        ExtUtils::Install
        ExtUtils::MakeMaker
        ExtUtils::Manifest
        ExtUtils::ParseXS
        File::Spec
        JSON
        JSON::PP
        Module::Build
        Module::Signature
        Parse::CPAN::Meta
        Test::Harness
        Test::More
        YAML
        YAML::Syck
        version
    );
    +{
        map {
            my $module = $_;
            my $local  = $self->local_module($module);
            ($module, $local);
        } @want
    }
}

sub environment_variables {
    my $self = shift;
    my @want = qw(
        AUTOMATED_TESTING
        HARNESS_OPTIONS
        LANG
        LANGUAGE
        PATH
        SHELL
    );
    push @want, grep { /^PERL/ } keys %ENV;
    +{ map { $_ => $ENV{$_} } sort @want };
}

sub special_variables {
    my $self = shift;
    +{
        '$^X' => $^X,
        '$UID' => $UID,
        '$EUID' => $EUID,
        '$GID' => $GID,
        '$EGID' => $EGID,
    };
}

sub write {
    my ($self, $key, $value) = @_;
    my $new_key = join ',', $self->{context}, $key;
    if (ref $value) {
        $self->{_ref_key}{$new_key} = 1;
        $value = $JSON->encode($value);
    }
    $self->{writer}->write( $new_key => $value );
}

sub finalize {
    my $self = shift;
    my $reader = Text::SimpleKeyValue::Reader->new(file => $self->{file});
    my @key = $reader->keys;
    my $out = {};
    for my $key (@key) {
        my @part = split /,/, $key;
        my $c = $out;
        for my $i (0 .. $#part-1) {
            $c = $c->{$part[$i]} ||= +{}
        }
        my $value = $reader->get($key);
        $value = $JSON->decode($value) if $self->{_ref_key}{$key};
        $c->{$part[-1]} = $value;
    }
    open my $fh, ">", $self->{finalfile} or die "$self->{finalfile}: $!";
    print {$fh} $JSON->encode($out);
}

1;
