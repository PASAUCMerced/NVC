#
#  output_raw.pl - produces RAW output
#  Copyright 1995-2011 Standard Performance Evaluation Corporation
#   All Rights Reserved
#
#  Authors:  Christopher Chan-Nui
#            Cloyce D. Spradling
#
# $Id: output_raw.pl 1198 2011-09-20 21:25:53Z CloyceS $

package Spec::Format::raw;

use strict;
use IO::File;
use Scalar::Util qw(reftype);

@Spec::Format::raw::ISA = qw(Spec::Format);

require 'format_raw.pl';

1;
