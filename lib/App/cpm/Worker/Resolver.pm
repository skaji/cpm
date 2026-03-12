package App::cpm::Worker::Resolver;
use v5.24;
use warnings;
use experimental qw(lexical_subs signatures);

sub new ($class, $ctx, %option) {
    bless { impl => $option{impl} }, $class;
}

sub work ($self, $ctx, $task) {

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
