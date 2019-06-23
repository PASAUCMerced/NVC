#
# flagutils.pl
#
# Copyright 2005-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: flagutils.pl 1164 2011-08-19 19:20:01Z CloyceS $

use strict;

require 'util.pl';

my $version = '$LastChangedRevision: 1164 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'flagutils.pl'} = $version;

# runspec's requirements are actually quite modest
require 'flagutils_common.pl';

1;
