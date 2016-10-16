package App::cpm::Resolver::MetaDB;
use strict;
use warnings;
use utf8;

use HTTP::Tiny;
use CPAN::Meta::YAML;
use App::cpm::version;
use App::cpm::Logger;

sub new {
    my ($class, %option) = @_;
    my $ua = HTTP::Tiny->new(timeout => 15, keep_alive => 1);
    bless { %option, ua => $ua }, $class;
}

sub resolve {
    my ($self, $job) = @_;
    my $res = $self->{ua}->get( "$self->{uri}/$job->{package}" );
    if ($res->{success}) {
        my $yaml = CPAN::Meta::YAML->read_string($res->{content});
        my $meta = $yaml->[0];
        my $version = $meta->{version} eq "undef" ? 0 : $meta->{version};
        if (my $req_version = $job->{version}) {
            if (!App::cpm::version->parse($version)->satisfy($req_version)) {
                App::cpm::Logger->log(
                    result => "WARN",
                    message => "Couldn't find $job->{package} $req_version (only found $version)",
                );
                return;
            }
        }
        my @provides = map {
            my $package = $_;
            my $version = $meta->{provides}{$_};
            $version = undef if $version eq "undef";
            +{ package => $package, version => $version };
        } sort keys %{$meta->{provides}};
        return {
            distfile => $meta->{distfile},
            version  => $meta->{version},
            provides => \@provides,
        };
    }
    return;
}

1;
