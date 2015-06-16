package Acme::CPAN::Installer::Master;
use strict;
use warnings;
use utf8;
use IO::Select;
use IO::Handle;

sub new {
    my $class = shift;
    bless { parent => 1, children => +{} }, $class;
}

sub is_parent { shift->{parent} }

sub handles {
    my $self = shift;
    map { @{$_}{qw(read write)} } values %{$self->{children}};
}

sub fork :method {
    my ($self, $cb) = @_;
    $self->is_parent or die;
    pipe my $read1, my $write1;
    pipe my $read2, my $write2;
    my $pid = fork // die;
    if ($pid == 0) {
        $self->{parent} = 0;
        close $_ for $read1, $write2, $self->handles;
        $write1->autoflush(1);
        $cb->($read2, $write1);
        exit;
    }
    close $_ for $write1, $read2;
    $write2->autoflush(1);
    warn "--> fork, child pid $pid\n" if $ENV{DEBUG};
    $self->{children}{$pid} = { read => $read1, write => $write2 };
}

sub wait_all_children {
    my $self = shift;
    $self->is_parent or die;
    while ( %{ $self->{children} } ) {
        my $pid = wait;
        if ($pid == -1) {
            warn "Something wrong, wait() returns -1\n";
            last;
        }
        delete $self->{children}{$pid};
        warn "--> reap $pid\n" if $ENV{DEBUG};
    }
}

sub can_read {
    my ($self, $second) = @_;
    $self->is_parent or die;
    my $select = IO::Select->new( map { $_->{read} } values %{$self->{children}} );
    my @ready = $select->can_read( $second ? $second : () );
    return @ready;
}

1;
