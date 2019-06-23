#
# vars.pl
#
# Copyright 1995-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: vars.pl 1198 2011-09-20 21:25:53Z CloyceS $

##############################################################################
# Initialize Variables
##############################################################################

use strict;
use Config;
use Cwd;
use Scalar::Util qw(reftype);

require 'vars_common.pl';

# List of SPEC(r) trademarked strings, for use by the formatters
# Values are "r" (registered trademark), "t" (trademark), and "s" (service mark)
# If a mark should be recognized as part of a larger word (say, for the
# "SPEC MPI" in "SPEC MPIM2007"), then make the value an array ref and set the
# second member to 1.
%::trademarks = (
                  'SPEC'           => 'r',
                  'SPEC Logo'      => 'r',
                  'SPECapc'        => 's',
                  'SPECchem'       => 'r',
                  'SPECclimate'    => 'r',
                  'SPECenv'        => 'r',
                  'SPECfp'         => 'r',
                  'SPECglperf'     => 'r',
                  'SPEChpc'        => 'r',
                  'SPECint'        => 'r',
                  'SPECjAppServer' => 'r',
                  'SPECjbb'        => 'r',
                  'SPEC JMS'       => 't',
                  'SPECjvm'        => 'r',
                  'SPECmail'       => 'r',
                  'SPECmark'       => 'r',
                  'SPECmedia'      => 's',
                  'SPEC MPI'       => [ 'r', 1 ],
                  'SPEComp'        => 'r',
                  'SPECompM'       => 'r',
                  'SPECompL'       => 'r',
                  'SPECopc'        => 's',
                  'SPECrate'       => 'r',
                  'SPECseis'       => 'r',
                  'SPECsfs'        => 'r',
                  'SPECviewperf'   => 'r',
                  'SPECweb'        => 'r',
                );

my $version = '$LastChangedRevision: 1198 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'vars.pl'} = $version;

1;

__END__
