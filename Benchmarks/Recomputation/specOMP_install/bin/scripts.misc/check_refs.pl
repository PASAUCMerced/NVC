#!specperl
#
# Doctool: check whether internal tags (<a name=xxx>)
# are actually referenced (<a href=#xxx>) and vice-versa.
# No support is provided for this script.
#
# Usage: check_refs.pl file(s)...
#
# j.henning 22-oct-2001
#
# Copyright 2001-2008 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: check_refs.pl 4 2008-06-26 14:09:58Z cloyce $

while ($file=shift @ARGV) {
  undef %defs;
  undef %refs;
  undef $num_defs;
  undef $num_refs;

  open (FILE, "<$file") or die "Can't open $file\n";
  print "$file:\n"; 

  while (<FILE>) {

    if (/name=\s*(\S+?)\s*>/i) {
       $defs{$1}++;
    }

    if (/href=\s*#(\S+?)\s*>/i) {
       $refs{$1}++;
    }

  }

  foreach $key (sort keys %defs) {
    $num_defs++;
    if (!defined $refs{$key}) {
      print "   '$key' is defined but is not referenced\n";
    }
  }

  foreach $key (sort keys %refs) {
    $num_refs++;
    if (!defined $defs{$key}) {
      print "   '$key' is referenced but is not defined\n";
    }
  }

  print "   Totals: ", $num_defs, " names defined \n";
  print "           ", $num_refs, " names referenced \n";

}
