#!/usr/bin/perl
#
# mark-external.pl - mark href links that go outside the current document with 
#       class="external"
# No support is provided for this script.
#
# Copyright 2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#  $Id: mark-external.pl 1164 2011-08-19 19:20:01Z CloyceS $
#
# As external references are marked:
#    - Leaves unchanged paragraphs alone.  
#    - Leaves <pre> sections alone.
#    - Re-wraps changed paragraphs.  Has an idea of what a "paragraph" is that
#      matches one doc writer's idea.  Your idea might differ.
#
# At the end, uses lynx-diff.sh to generate (and keep) text versions, for
# comparision purposes.  This procedure should NOT create differences that can
# be seen by lynx.  If it does, something went wrong.
#
# Usage:
#    1. You probably want to start by making a working directory that
#       has copies of the html files you care about.
#    2. cd to that directory 
#    3. and just run this script
#
# Outputs:
#    - directory ./out contains modified html files
#    - both current dir and outdir get plaintext (lynx) versions as 
#        file.lynx-txt
#    - current dir also gets side-by-side diffs of the lynx versions, as 
#        file.lynx-diff.txt
#
# j.henning Aug 2011

use strict;
use Text::Wrap qw ($columns &wrap $huge);
use Cwd;
use FindBin qw($Bin);

my $scriptdir = $Bin;

$columns = 131;             # desired wrap width, if paragraph is changed
$huge = "overflow";         # if a single word is > $columns wide, leave it alone
$Text::Wrap::unexpand = 0;  # no tab characters plese

my $lynxdiff = "$scriptdir/lynx-diff.sh";
if ( ! -x $lynxdiff ) {
   die "lynxdiff is needed to verify that output has no unexpected diffs";
}

undef $/;                   # slurp whole files
my $debug = 0;

my $TMPDIR;
if ( defined $ENV{"TMPDIR"} ) {
   $TMPDIR = $ENV{"TMPDIR"};
} elsif (defined $ENV{"USER"} ) {
   $TMPDIR = "/tmp/" . $ENV{"USER"};
} else {
   $TMPDIR = "/tmp";
}

my $outdir = "./out";
system "mkdir -p $outdir";
die "eh?" if ! -d "$outdir";
system "rm -f *lynx*txt *diff*txt $outdir/*diff*txt $outdir/*lynx*txt";

my @files = split " ", `ls *html`;

for my $file (@files) {
   my $columnpos = 0;
   # no effect when slurp mode! chomp $file;
   $file =~ s/\n//;
   print                "opening '$file'";  
   $columnpos += length "opening '$file'";
   if ($debug) { 
      print "\n";
      $columnpos = 0;
   }
   open IN, "<$file" or die "can't open $file: $!\n";
   my $outfile = "$outdir/$file";
   open OUT, ">$outfile" or die "can't open output $outfile: $!\n";

   my $doc = <IN>;
   close IN;

   my @paragraphs;

   # Break the html doc into "paragraphs" using this particular doc writer's idea of good break points:
   #   - The usual: multiple blank lines
   #   - if </p>, </li>, etc are the last token on the line
   #   - or if we encounter <pre> (which will get special processing to leave its contents alone)

   while ($doc) {
      #print length $doc, "\n" if $debug > 4;
      #print "doc:'$doc'\n" if length $doc < 82 and $debug > 4;
      my $para;
      my $delim;
      if ($doc =~ /^\s*<pre[^>]*>/s) {      # does line already start with <pre> ?
         $doc =~ s{(.*?)(</pre>(.*?\n)(\s*\n)*)}{}s;   # slurp to </pre> (and whatever trails on that line)
         $para = $1;
         $delim = $2;
         #print "para:'$para'\ndelim:'$delim'\n";
         push @paragraphs, $para . $delim;
      } else {
         # slurp up to next delimiter, treating <pre> specially
         my $breaks =   '\n(\s*\n)+'          # traditional 2+ linefeeds
                      . '|</li>\s*\n'          # various close tags
                      . '|</p>\s*\n'           # ... if they are last
                      . '|</td>\s*\n'          #     tag on line
                      . '|</th>\s*\n'          #     
                      . '|</div>\s*\n'         
                      . '|</ul>\s*\n'
                      . '|</ol>\s*\n'
                      . '|</h\d+>\s*\n'
                      . '|<tr[^>]*>\s*\n'      # and a few open tags, if they are last on line
                      . '|<td[^>]*>\s*\n'
                      . '|<table[^>]*>\s*\n'
                      . '|<ol[^>]*>\s*\n'
                      . '|<ul[^>]*>\s*\n'
                      . '|(\n)*$'                   # and end of whole doc!
                      ;
         #print "breaks: '$breaks'\n"; exit;
         $doc =~ s{(.*?)(<pre[^>]*>|$breaks)}{}s;
         $para = $1;
         $delim = $2;
         if ($delim !~ /<pre[^>]*>/) {
            push @paragraphs, $para . $delim;
         } else {
            # found <pre>.  Spit out what we have, then slurp in all until </pre>
            push @paragraphs, $para . "\n";
            $para = $delim;                  # after this, <pre> will ONLY occur at start of para
            $doc =~ s{(.*?)(</pre>(.*?\n))}{}s;
            $para .= $1;
            $delim = $2;
            push @paragraphs, $para . $delim;
         }
      }
   }
   print "split into " . scalar(@paragraphs) . " paragraphs \n" if $debug;

   # Now, analyze the "paragraphs"

   my $total_added = 0;
   my $total_removed = 0;
   my $total_removed_because_samefile = 0;
   for my $para (@paragraphs) {
      my $unchangedp = $para;
      my $added = 0;
      my $removed = 0;
      my $removed_because_samefile = 0;

      # nothing to do if it's a <pre>, or if it's nothing but blanks
      if ($para =~ m/^<pre[ >]/ or $para =~ /^(\s*\n)+$/s) {
         print "not touching: '$para'\n" if $debug;
         print OUT $para;
         next;
      }

      my $firstlineindent = "";   # how is this para indented?
      if ($para =~ /^( +)/) {
         $firstlineindent = $1;
      }
      my $otherindent = $firstlineindent;
      my @lines = split "\n", $para, 2;
      if ($lines[1] =~ /^( +)(\S)/) {
         $otherindent = $1;
      }

      my $prevpos = 0;   # in case we need to back up and change something
      
      # fixups if needed
      # non-greedy match for <a ... >, possibly spanning lines; "g" so it can feed the "while"
      while ($para =~ /(<a\b.*?>)/gs) {  
         my $a = $1;
         my $newpos = pos($para);
         # don't touch "<a name"!
         if ($a !~ /name=/) {
            $a =~ m/href="(.*?)"/;
            my $dest = $1;
            (my $destfile, my $destanchor) = split "#", $dest;
            if ($destfile eq "" || $destfile eq $file) { # local ref?
               # yes, local.  Should NOT say external
               if ($a =~ m/class="external"/s) {
                  pos($para) = $prevpos;
                  $para =~ s/\G(.*?<a\b.*?)class="external"/\1/s;
                  $removed++;
                  $removed_because_samefile++ if $destfile eq $file;
               }
            } else {
               # remote.  Mark it external, unless already marked.
               if ($a !~ m/class="external"/s) { 
                  pos($para) = $prevpos;
                  $para =~ s/\G(.*?<a\b)/\1 class="external"/s; 
                  $added++;
               }
            }
         }
         pos($para) = $newpos;
         $prevpos = pos($para);
      }

      # if we made changes, re-wrap it.

      if (($added + $removed) == 0) {
         print OUT $para;
      } else {
         $total_added += $added;
         $total_removed += $removed;
         $total_removed_because_samefile += $removed_because_samefile;
         print "\n==========\nwas:\n'$unchangedp'\n" if $debug;
         print "now:\n'$para'\n" if $debug > 1;
         @lines = split "\n", $para;
         $para = "";
         for my $l (@lines) {  # first, we join all lines into one
            $l =~ s/^\s+//;    # no leading blanks
            $l =~ s/\s*$/ /;   # drop all but one trailing
            $para .= $l;
         }
         print "joined:\n'$para'\n" if $debug > 1;
         $para = wrap($firstlineindent, $otherindent, $para);
         # if multiple whitespace at end, let's keep that
         if ($unchangedp =~ m/(\n(\s*\n)+)$/s) {
            $para .= $1;
         } else {
            $para .= "\n";
         }
         print "wrapped: with indents '$firstlineindent' '$otherindent' \n'$para'\n\n" if $debug;
         print OUT "$para";
      }
   }
   close OUT;
   my $spaceneeded = 40 - $columnpos;
   if ($spaceneeded > 0) {
      print " " x $spaceneeded;
   }
   printf "%3d added\t", $total_added if $total_added;
   printf "%3d removed\t", $total_removed if $total_removed;
   print "($total_removed_because_samefile because samefile)" if $total_removed_because_samefile;
   print "\n";

   #
   # Generate lynx diff
   # 

   system "$lynxdiff -s -k -o $file.lynx-diff.txt -t $TMPDIR -w 80 $file $outfile";
   my $sum1;
   my $sum2;
   system "mv $TMPDIR/lynx.out1.txt $file.lynx.txt";
   system "mv $TMPDIR/lynx.out2.txt $outfile.lynx.txt";
   ($sum1) = split " ", `cksum $file.lynx.txt`;
   ($sum2) = split " ", `cksum $outfile.lynx.txt`;
   print "cksums: $sum1 $sum2\n" if $debug;
   if ($sum1 != $sum2) {
      print "!!!! WARNING !!!!! lynx version of $file does not match output\n";
   }
}
