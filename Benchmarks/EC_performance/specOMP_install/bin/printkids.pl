#!/home/cc/specOMP_install/bin/specperl
#!/home/cc/specOMP_install/bin/specperl -d
#!/usr/bin/perl
#
# printkids.pl
# No support is provided for this script.
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: printkids.pl 1640 2012-05-09 20:12:09Z CloyceS $
#
# Print time for each child and as much of the command as fits on 1 line
# Usage: cd to run directory and then say 'printkids.pl'
# J.Henning 5 May 1999

open SPECOUT, '<speccmds.out' or die "Can't open speccmds.out for reading: $!\n";
print "  Seconds  Command\n";

while (<SPECOUT>) {
   if (/child started:\s*\d+,\s*\d+,\s*\d+,\s*(?:pid=)?\d+,\s*\'([^\']+)\'/) {
      $command = $1;
      }
   if (/child finished:\s*\d+,\s*\d+,\s*\d+,\s*(?:sec=)?(\d+),\s*(?:nsec=)?(\d+)/){
      $laps = ($1 + ($2/1000000000));
      $total += $laps;
      printf ("%9.2f %s\n", $laps, substr($command,12,69));
      }
   if (/runs elapsed time:\s*\d+,\s*\d+,\s*([0-9.]+)/) {
      $runs_laps = $1;
      }
   }
printf ("=========\n%9.2f Total by adding children      \n", $total);
printf ("%9.2f Total according to speccmds.out\n", $runs_laps);

