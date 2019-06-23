#
# os.pm
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: os.pl 1164 2011-08-19 19:20:01Z CloyceS $

use strict;

my $version = '$LastChangedRevision: 1164 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'os.pl'} = $version;

# It's really _all_ common
require 'os_common.pl';

1;
