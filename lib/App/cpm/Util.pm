package App::cpm::Util;
use strict;
use warnings;

use File::Spec;

sub maybe_abs {
    my ($cwd, $path) = @_;
    if (File::Spec->file_name_is_absolute($path)) {
        return $path;
    } else {
        File::Spec->canonpath(File::Spec->catdir($cwd, $path));
    }
}

1;
