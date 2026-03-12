package App::cpm::Task;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);
use CPAN::DistnameInfo;

sub new ($class, %option) {
    my $self = bless {%option}, $class;
    $self->{uid} = $self->_uid;
    $self;
}

sub uid ($self) { $self->{uid} }

sub _uid ($self) {
    my $type = $self->type;
    if (grep { $type eq $_ } qw(fetch configure install)) {
        "$type " . $self->distfile;
    } elsif ($type eq "resolve") {
        "$type " . $self->{package};
    } else {
        die "unknown type: " . ($type || "(undef)");
    }
}

sub distfile ($self) {
    $self->{distfile} || $self->{uri};
}

sub distvname ($self) {
    return $self->{_distvname} if $self->{_distvname};
    if ($self->{distfile}) {
        $self->{_distvname} ||= CPAN::DistnameInfo->new($self->{distfile})->distvname;
    } elsif ($self->{uri}) {
        $self->{uri};
    } elsif ($self->{package}) {
        $self->{package};
    } else {
        "UNKNOWN";
    }
}

sub distname ($self) {
    $self->{_distname} ||= CPAN::DistnameInfo->new($self->distfile)->dist || 'UNKNOWN';
}

sub cpanid ($self) {
    $self->{_cpanid} ||= CPAN::DistnameInfo->new($self->distfile)->cpanid || 'UNKNOWN';
}

sub type ($self) {
    $self->{type};
}

sub in_charge ($self, @argv) {
    @argv ? $self->{in_charge} = $argv[0] : $self->{in_charge};
}

sub is_success ($self) {
    $self->{ok};
}

sub equals ($self, $that) {
    $self->uid eq $that->uid;
}

sub merge ($self, $that) {
    for my $key (keys %$that) {
        $self->{$key} = $that->{$key};
    }
    $self;
}

1;
