package App::cpm::Worker::Resolver;
use strict;
use warnings;

sub new {
    my ($class, $ctx, %option) = @_;
    bless { impl => $option{impl} }, $class;
}

sub work {
    my ($self, $ctx, $task) = @_;

    local $ctx->{logger}{context} = $task->{package};
    my $result = $self->{impl}->resolve($ctx, $task);
    if ($result and !$result->{error}) {
        $result->{ok} = 1;
        my $msg = sprintf "Resolved %s (%s) -> %s", $task->{package}, $task->{version_range} || 0,
            $result->{uri} . ($result->{from} ? " from $result->{from}" : "");
        $ctx->log($msg);
        return $result;
    } else {
        $ctx->log($result->{error}) if $result and $result->{error};
        $ctx->log(sprintf "Failed to resolve %s", $task->{package});
        return { ok => 0 };
    }
}

1;
