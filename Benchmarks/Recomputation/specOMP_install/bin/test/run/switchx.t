#!specperl

BEGIN {
  use TestInit;
#    chdir 't' if -d 't';
#    @INC = '../lib';
}

require './test.pl';
use File::Spec::Functions;

print runperl( switches => ['-x'], progfile => catfile(curdir(), 'run', 'switchx.aux') );
