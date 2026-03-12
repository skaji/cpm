package App::cpm::Requirement;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

use App::cpm::version;

sub new ($class, @argv) {
    my $self = bless { requirement => [] }, $class;
    $self->add(@argv) if @argv;
    $self;
}

sub empty ($self) {
    @{$self->{requirement}} == 0;
}

sub has ($self, $package) {
    my ($found) = grep { $_->{package} eq $package } @{$self->{requirement}};
    $found;
}

sub add ($self, @argv) {
    my %package = (@argv, @argv % 2 ? (0) : ());
    for my $package (sort keys %package) {
        my $version_range = $package{$package};
        if (my ($found) = grep { $_->{package} eq $package } @{$self->{requirement}}) {
            my $merged = eval {
                App::cpm::version::range_merge($found->{version_range}, $version_range);
            };
            if (my $err = $@) {
                if ($err =~ /illegal requirements/) {
                    $@ = "Couldn't merge version range '$version_range' with '$found->{version_range}' for package '$package'";
                    warn $@; # XXX
                    return; # should check $@ in caller side
                } else {
                    die $err;
                }
            }
            $found->{version_range} = $merged;
        } else {
            push @{$self->{requirement}}, { package => $package, version_range => $version_range };
        }
    }
    return 1;
}

sub merge ($self, $other) {
    $self->add(map { ($_->{package}, $_->{version_range}) } @{ $other->as_array });
}

sub delete :method ($self, @package) {
    for my $i (reverse 0 .. $#{ $self->{requirement} }) {
        my $current = $self->{requirement}[$i]{package};
        if (grep { $current eq $_ } @package) {
            splice @{$self->{requirement}}, $i, 1;
        }
    }
}

sub as_array ($self) {
    $self->{requirement};
}

1;
