#!/bin/bash

eval "$($_TEST_PERL -Mlocal::lib=$_TEST_DIR,--quiet)"
exec $_TEST_PERL xt/37_global_local_lib/main.pl
