#
# log.pl
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: log.pl 1164 2011-08-19 19:20:01Z CloyceS $

use strict;

my $version = '$LastChangedRevision: 1164 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'log.pl'} = $version;

$::log_handle = undef;

require 'log_common.pl';

1;
