package Trial;
use v5.42;

use Moose;
with 'Dist::Zilla::Role::FileMunger';

sub munge_file ($self, $file) {
    return if !$ENV{DZIL_RELEASING};
    return if $file->name ne "lib/App/cpm.pm";

    my @line;
    for my $line (split /\n/, $file->content, -1) {
        if ($line =~ /^our \$TRIAL/) {
            my $trial_line = sprintf 'our $TRIAL = %d;', $self->zilla->is_trial ? 1 : 0;
            push @line, $trial_line;
        } else {
            push @line, $line;
        }
    }
    $file->content(join "\n", @line);
}
