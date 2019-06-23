#!/home/cc/specOMP_install/bin/specperl
#!/home/cc/specOMP_install/bin/specperl -d
#!/usr/bin/perl
#
# printpath.pl
# No support is provided for this script.
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: printpath.pl 1640 2012-05-09 20:12:09Z CloyceS $
# Print an NT path with some carriage returns for legibility
# Include hats so the output can be captured for re-use if desired.
# J.Henning 22 April 1999
#
@path = split ";", $ENV{'PATH'};
$path[1] =~ s/^PATH=//;
print "\nPATH=^\n";
print join (";^\n", @path), "\n";
