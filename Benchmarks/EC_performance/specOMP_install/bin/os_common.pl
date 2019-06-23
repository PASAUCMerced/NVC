#
# os.pm
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: os_common.pl 1164 2011-08-19 19:20:01Z CloyceS $

use strict;

my $version = '$LastChangedRevision: 1164 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'os_common.pl'} = $version;

# Set up a process group if we can
sub setProcGrp {
    my ($config) = @_;
    eval "setpgrp;";
    if ($@) {
# This isn't much use if we never define handle_sigint...
#	$SIG{'INT'} = 'handle_sigint' 
    } else {
	$config->{'setpgrp_enabled'} = 1;
    }
}

sub initialize_os {
    my ($config) = @_;
    setProcGrp($config) if istrue($config->setprocgroup);
}

1;
