package App::cpm::Resolver::CPANfile;
use strict;
use warnings;
use Module::CPANfile;

sub new {
    my ($class, %option) = @_;
    my $path = $option{path} || "cpanfile";
    my $cpanfile = Module::CPANfile->load($path);
    bless { cpanfile => $cpanfile }, $class;
}

sub resolve {
    my ($self, $job) = @_;
    my $option = $self->{cpanfile}->options_for_module($job->{package});
    return unless $option;

    my $uri;
    if ($uri = $option->{git}) {
        return +{
            source => "git",
            uri => $uri,
            ref => $option->{ref},
        };
    } elsif ($uri = $option->{dist}) {
        my $source = $uri =~ m{^file://} ? "local" : "http";
        return +{
            source => $source,
            uri => $uri,
        };
    }
}


1;
