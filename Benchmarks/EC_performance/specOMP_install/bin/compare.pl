#
# compare.pl
#
# Copyright 1995-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: compare.pl 1727 2012-07-24 19:42:08Z CloyceS $
#
use strict;
use Digest::MD5;
use IO::Uncompress::Bunzip2 qw(:all);

use IO::File;
use IO::Seekable;
use IO::Scalar;

my $sddebug = 0;

my $version = '$LastChangedRevision: 1727 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'compare.pl'} = $version;

sub spec_diff_get_next_line {
    my ($fh) = @_;
    my $line;
    if ($fh->eof) {
	return undef;
    }
    ($line = $fh->getline) =~ tr/\015\012//d;
    $line = '' if ($line =~ m/program\s+(stop|end|terminated)/oi);
    return $line;
}

## ############
## sub                   spec_diff
## ############

## compare two files semi-intelligently (with knowledge of number formats, etc)

# arguments:
#   file1:   source file to compare against
#   file2:   file generated during benchmark run
#   opts:    hash ref of various tunables

sub spec_diff {
    my ($file1, $file2, $opts) = @_;
    my (@rc, $pos, $len);
    my ($line, $line1, $line2);
    my ($fh1, $fh2);   # W.S.
    my $max = { 'abstol' => 0,
		'reltol' => 0,
	    };
    my $min = { 'abstol' => 999999,
		'reltol' => 999999,
	    };
    my $deltas = { 'abstol' => [],
		   'reltol' => [],
	    };
    my $errcnt = { 'abstol'  => 0,
		   'reltol'  => 0,
		   'skiptol' => 0,
		   'obiwan'  => 0,
	       };
    my $lines = $opts->{'lines'};
    $opts->{'calctol'} = 1 if $opts->{'histogram'};
    if ($opts->{'calctol'}) {
	# To get accurate results, you must look at *all* differences
	# We'll still only return the requested number, though.
	$lines = -1;
    }
    my $rc;

    ## $ugly_pat is a constant.. a regular expression on a grand scale.
    ## It breaks the string it is looking at into the elements of
    ## scientific notation
    ##   $1 :: any characters preceeding a floating point number (optional)
    ##   $2 :: the floating point number
    ##   $3 :: any characters after the floating point number (optional)
    ##   The decimal point is required. The floating point may include
    ##   an (optional) exponential notation as in e+23 or E-3.
    ##   
    my ($ugly_pat) = "(.*?)([+-]?(?:[0-9]+\\.[0-9]*|[0-9]*\\.[0-9]+|[0-9]+))([dDgGeE][+-][0-9]*|)(.*)";

    ## $check_floating is set if relative or absolute arguments are given
    my ($check_floating) = ((defined $opts->{'reltol'}  && $opts->{'reltol'}  ne '')|| 
                            (defined $opts->{'skipreltol'}  && $opts->{'skipreltol'}  ne '')||
                            (defined $opts->{'abstol'}  && $opts->{'abstol'}  ne '')||
                            (defined $opts->{'skipabstol'}  && $opts->{'skipabstol'}  ne '')||
                            (defined $opts->{'skipobiwan'}  && $opts->{'skipobiwan'}  ne '')||
			    (defined $opts->{'obiwan'}  && $opts->{'obiwan'}  ne ''))?1:0;

    $opts->{'skiptol'}    = 0 if $opts->{'skiptol'} eq '';
    $opts->{'obiwan'} = 1 if $check_floating;   # Whenever tolerances are set

    $check_floating = 1 if (defined $opts->{'floating'} && $opts->{'floating'});
    $opts->{'cw'} = 1 if $check_floating;   # Whenever floatcompare is explicit

    # We don't want skiptol to turn on obiwan or compress whitespace without
    # the user requesting it.
    $check_floating = 1 if (defined $opts->{'skiptol'} && $opts->{'skiptol'} != 0);

    my ($data1, $data2) = ('', '');
    $fh1 = new IO::File "<$file1";
    return ("Couldn't open '$file1': $!\n") if !defined $fh1;
    if ($file1 =~ /\.bz2$/) {
      my $status = bunzip2 $fh1 => \$data1, 'AutoClose' => 1;
      if (!$status) {
        return ("Decompression of '$file1' failed: $Bunzip2Error\n");
      }
      $fh1 = new IO::Scalar \$data1;
      return ("Couldn't open uncompressed '$file1': $!\n") if !defined $fh1;
    }
    $fh2 = new IO::File "<$file2";
    return ("Couldn't open '$file2': $!\n") if !defined $fh2;
    if ($file2 =~ /\.bz2$/) {
      my $status = bunzip2 $fh2 => \$data2, 'AutoClose' => 1;
      if (!$status) {
        return ("Decompression of '$file2' failed: $Bunzip2Error\n");
      }
      $fh2 = new IO::Scalar \$data2;
      return ("Couldn't open uncompressed '$file2': $!\n") if !defined $fh2;
    }
    if ($opts->{'binary'}) {
	binmode $$fh1, ':raw';
	binmode $$fh2, ':raw';
    }

    # If we don't have to do any fancy stuff, do a quick check to see if the
    # files are identical. If not, reset the file pointers and do
    # the slow check to find out where they differ
    if (!$check_floating && !$opts->{'calctol'} && !$opts->{'ignorecase'}) {
        my ($md5a, $md5b);
        $md5a = new Digest::MD5;
        $md5b = new Digest::MD5;
        # Digest::MD5's addfile method doesn't work with IO::Scalar filehandles
	#$md5a->addfile($fh1);
        md5_addfile($md5a, $fh1);
	#$md5b->addfile($fh2);
        md5_addfile($md5b, $fh2);

	if ($md5a->hexdigest eq $md5b->hexdigest) {
	    return (0);
	} elsif ($opts->{'binary'}) {
	    return (1, "Binary files $file1 and $file2 do not match.\n");
	}
	$fh1->seek(0, SEEK_SET);
	$fh2->seek(0, SEEK_SET);
    }

    $line = 0;
    while (1) {
	last if $fh1->eof() && $fh2->eof(); # Files were equal or we saw all errors

	if ($opts->{'binary'}){
            $line++;
	    $line1 = $fh1->getc;
	    $line2 = $fh2->getc;
	} else {
            # If ignoring whitespace, skip all lines that are empty
	    do {
	        $line1 = spec_diff_get_next_line($fh1);
	    } while ($opts->{'cw'} && defined($line1) && $line1 =~ m/^\s*$/);
	    do {
	        $line++;
	        $line2 = spec_diff_get_next_line($fh2);
	    } while ($opts->{'cw'} && defined($line2) && $line2 =~ m/^\s*$/);
        }
        last if $line1 eq '' && $line2 eq '' && $fh1->eof() && $fh2->eof();
	if ($fh1->eof() && $line1 eq '') { push (@rc, "'$file2' long");  last; }
	if ($fh2->eof() && $line2 eq '') { push (@rc, "'$file2' short"); last; }

	# Simple optimization from Alexander Ostanewich <alexo@lab.sun.mcst.ru>
	# Even for FP compares, if the lines are the same then the numbers
	# are the same.
        if (!$opts->{'calctol'}) {
          if ($opts->{'ignorecase'}) {
            next if (lc($line1) eq lc($line2));
          } else {
            next if ($line1 eq $line2);
          }
        }

	$pos = 0;
	if (!$check_floating) {
	    # Do the simple case here, integer file, so lines have to match
	    if (defined ($rc = diff_at($line1, $line2, $opts))) {
	      $pos += $rc;

	      ## format an output line
	      push @rc, format_error_line($line, $line1, $line2, $pos, $opts);
	    }
	} else {
	    # Work on temporary copies of the lines
	    my ($buf1, $buf2);
            if ($opts->{'binary'}) {
		$buf1 = ord($line1);
		$buf2 = ord($line2);
	    } else {
	        $buf1 = $line1;
	        $buf2 = $line2;
	    }
	    my ($pre1, $mant1, $exp1, $post1, $val1, $mant1_dec);
	    my ($pre2, $mant2, $exp2, $post2, $val2, $mant2_dec);

	    my $error = 0;
	    my $isnum = 0;
	    while ($buf1 && !$error) {
		$isnum = 0;
		if ($buf1 =~ m/^$ugly_pat$/o) { ## breakup A -- there must
                                                ## be a floating point value
		    $pre1   = $1; ## string before the floating point value
		    $mant1  = $2; ## the mantissa of the floating point value
		    $exp1   = $3; ## the exponent of the floating point value
		    $post1  = $4; ## string after the floating point value
		    if ($buf2 =~ m/^$ugly_pat$/o) { ## breakup B
			$pre2   = $1; ## string before the floating point value
			$mant2  = $2; ## the mantissa of the floating point value
			$exp2   = $3; ## the exponent of the floating point value
			$post2  = $4; ## string after the floating point value
			$isnum  =  1;
			if ($sddebug) {
			    print "1: $line1\n";
			    print "2: $line2\n";
			    print "<: mant1='$mant1', exp1='$exp1'\n";
			    print "<: mant2='$mant2', exp2='$exp2'\n";
			    print "<: pre1='$pre1', post1='$post1'\n";
			    print "<: pre2='$pre2', post2='$post2'\n";
			}

			# diff_at() is only called if pre1 and pre2 don't match
			if ((($opts->{'ignorecase'} && (lc($pre1) ne lc($pre2)))
                            || (!$opts->{'ignorecase'} && ($pre1 ne $pre2)))
                            && defined ($rc = diff_at($pre1, $pre2, $opts))) {

			    ## first order error handling
			    $error = 1;
			    $pos += $rc; ## Increment the position
				         ## by where the difference was
			                 ## found.
			    ## end of error specific block
			} else {
			    ## normal processing
			    $pos += length $pre2;
			    $len  = length ("$mant2$exp2");
			    $error = 1;

			    $exp1=~s/^[Dd]/e/;
			    $exp2=~s/^[Dd]/e/;
                            # Get the numeric value
			    $val1 = "$mant1$exp1" + 0;
			    $val2 = "$mant2$exp2" + 0;

                            # Remove that annoying leading character
			    $exp1 = substr($exp1, 1);
			    $exp2 = substr($exp2, 1);

			    # We convert everything to doubles, which have
			    # precision limitations, so arbitrarily knock off
			    # values less than 1e-300
			    $exp1 = 0 if ($exp1 < -300);
			    $exp2 = 0 if ($exp2 < -300);

			    $error = 0 if ($val1 == $val2);
			    my $delta;

			    # abstol processing
			    if ($opts->{'calctol'} ||
				($error && defined $opts->{'abstol'})) {
				$delta = $opts->{'abstol'}+0;
				if ($error &&
				    $val1 - $delta <= $val2 &&
				    $val1 + $delta >= $val2) {
				    $error = 0 if defined($opts->{'abstol'});
				} elsif ($error && $opts->{'skipabstol'} > 0) {
				    $opts->{'skipabstol'}--;
				    $errcnt->{'abstol'}++;
				    $error = 0;
				}
				$errcnt->{'abstol'}++ if ($error);
				$delta = abs($val1 - $val2);
				push @{$deltas->{'abstol'}}, $delta;
				$min->{'abstol'} = $delta if ($delta < $min->{'abstol'});
				$max->{'abstol'} = $delta if ($delta > $max->{'abstol'});
			    }

			    # reltol processing
			    if ($opts->{'calctol'} ||
				($error && defined $opts->{'reltol'})) {
				$delta = abs($val1 * $opts->{'reltol'});
				if ($error &&
				    $val1 - $delta <= $val2 &&
				    $val1 + $delta >= $val2) {
				    $error = 0 if defined($opts->{'reltol'});
				} elsif ($error && $opts->{'skipreltol'} > 0) {
				    $opts->{'skipreltol'}--;
				    $errcnt->{'reltol'}++;
				    $error = 0;
				}
				$errcnt->{'reltol'}++ if ($error);
				if ($val1 != 0) {
				    $delta = abs(abs($val1 - $val2) / $val1);
				    push @{$deltas->{'reltol'}}, $delta;
				    $min->{'reltol'} = $delta if ($delta < $min->{'reltol'});
				    $max->{'reltol'} = $delta if ($delta > $max->{'reltol'});
				}
			    }

			    # obiwan processing
			    if (defined($opts->{'obiwan'}) ||
				defined($opts->{'skipobiwan'}) ||
				defined($opts->{'calctol'})) {
				$mant1_dec = index($mant1, '.');
				if ($mant1_dec < 0) {
				    $mant1_dec = 0;
				} else {
				    $mant1_dec = (length $mant1) - $mant1_dec - 1;
				}
				$mant2_dec = index($mant2, '.');
				if ($mant2_dec < 0) {
				    $mant2_dec = 0;
				} else {
				    $mant2_dec = (length $mant2) - $mant2_dec - 1;
				}
				my $mant1_val = $mant1;
				my $mant2_val = $mant2;
				$delta = $mant1_dec;
				$delta = $mant2_dec if $mant2_dec > $delta;
				$mant1_val = $mant1 * (10 ** $delta);
				$mant2_val = $mant2 * (10 ** $delta);
				$delta = $exp1 - $exp2;
				if ($delta < 0) {
				    $mant2_val = $mant2_val * (10 ** -$delta);
				} else {
				    $mant1_val = $mant1_val * (10 ** $delta);
				}
				if ($error &&
				    ($mant1_val != $mant2_val) &&
                                    (abs($mant1_val - $mant2_val) < 1.5)) {
				    $errcnt->{'obiwan'}++;
				    if ($opts->{'skipobiwan'} > 0) {
					$opts->{'skipobiwan'}--;
					$error = 0;
				    } elsif ($opts->{'obiwan'}) {
					$error = 0;
				    }
				}
			    }

			    ## error or not, this gets done...
			    $pos += $len;
			    $buf1 = $post1; ## shift fwd to string past number
			    $buf2 = $post2; ## shift fwd to string past number
			}

			## end of successful match to a floating point in $b
		    } else {
			## floating point number not found
			$error = 1;
			$pos += diff_at($pre1, $buf2, $opts);
		    }
		    ## end of successful match to a floating point in $a

		  } elsif ((($opts->{'ignorecase'} && (lc($buf1) ne lc($buf2)))
                            || (!$opts->{'ignorecase'} && ($buf1 ne $buf2)))
                            && defined ($rc = diff_at($buf1, $buf2, $opts))) {
		    $pos += $rc; ## increment position by how far diff spans
		    $error = 1;
		} else {
		    $buf1 = '';
		}

		## error handling
		if ($error) {	## format an error string for output
		    print "error: isnum=$isnum, skiptol=$opts->{'skiptol'}, line=$line, buf1='$buf1', val1='$val1', val2='$val2'\n" if ($sddebug);
		    if ($isnum && $opts->{'skiptol'} > 0) {
			$opts->{'skiptol'}--;
			$errcnt->{'skiptol'}++;
			$error = 0;
		    } else {
		      push @rc, format_error_line($line, $line1, $line2,
						  $pos, $opts);
		      last;
		    }
		}
	    } ## END OF while $buf1 and not error LOOP
	}

	# If we exceed the number of error lines we are interested in, then
	# don't do any more work.
	last if ($lines >= 0 && @rc >= $lines);
    }

    my $num_errs = @rc+0;
    my @errstats = ();
    if ($opts->{'histogram'}) {
	push @errstats, 'Absolute differences:';
	push @errstats, do_histogram($deltas->{'abstol'});
	push @errstats, '', 'Relative differences:';
	push @errstats, do_histogram($deltas->{'reltol'}), '';
    }
    if ($opts->{'calctol'}) {
	push @errstats, 'Calculated tolerances:';
	foreach my $type (qw(abstol reltol obiwan skiptol)) {
	    if (exists($max->{$type}) && ($max->{$type} > 0)) {
		push @errstats, sprintf "Maximum $type: %-10.5e", $max->{$type};
	    }
	    if (exists($min->{$type}) && ($min->{$type} < 999999)) {
		push @errstats, sprintf "Minimum $type: %-10.5e", $min->{$type};
	    }
	    if (exists($errcnt->{$type}) && ($errcnt->{$type} > 0)) {
		push @errstats, "# of $type errors: ".$errcnt->{$type};
	    }
	    if (exists($opts->{"skip$type"}) && ($opts->{"skip$type"} > 0)) {
		push @errstats, "# of skip$type unused: ".$opts->{"skip$type"};
	    }
	}
	# Get rid of all but the requested number of error lines
	@rc = splice(@rc, 0, $opts->{'lines'}) if ($opts->{'lines'} >= 0);
	unshift @rc, @errstats;
    }

    # a non-intuitive use of grep to add eol at end of the strings in @rc
    grep(s/$/\n/, @rc);
    return ($num_errs, @rc);
}

## ############
## sub                   diff_at
## ############

## looks for point of differentiation in two strings (while ignoring
## white space, if that option is specified). The value returned is
## in reference to the uncollapsed second string.

# Fairly slow but should be adequate for our purposes
sub diff_at {
    my ($a, $b, $opts) = @_;

    if ($opts->{'cw'}) {
	# If collapsing whitespace, remove all leading and trailing whitespace
	# and turn all whitespace sequences into a single space
	$a =~ s/\s+$//g;
	$b =~ s/\s+$//g;
	$a =~ s/^\s+//g;
	$b =~ s/^\s+//g;
	$a =~ s/\s+/ /g;
	$b =~ s/\s+/ /g;
    }
    my @a = split (//, $a);	# create array of characters from strings
    my @b = split (//, $b);
    my $pos = 0;
    my $b_pos = 0;
    my $a_lastwaswhite = 0;
    my $b_lastwaswhite = 0;
    while (1) {
      if (!@a) {
	return undef if (!@b);
	for my $bchar (@b) {
	  return $b_pos unless ($bchar eq ' ');
	}
	return undef;
      }
      if (!@b) {
	return $b_pos;
      }

      # Get the characters
      $a = shift(@a);
      $b = shift(@b);
      $b_pos++;

      # Collapse whitespace (if necessary)
      while($opts->{'cw'} && $a_lastwaswhite && $a eq ' ') {
	$a = shift(@a);	## reuse the $a variable to hold single char
      }
      while($opts->{'cw'} && $b_lastwaswhite && $b eq ' ') {
	$b = shift(@b);
	$b_pos ++;
      }

      return $b_pos if (($opts->{'ignorecase'} && (lc($a) ne lc($b))) ||
			(!$opts->{'ignorecase'} && ($a ne $b)));

      $a_lastwaswhite = $a eq ' ';
      $b_lastwaswhite = $b eq ' ';
    }
    return undef;
}

sub md5_addfile {
  my ($md5, $fh) = @_;

  if (ref($fh) eq 'IO::Scalar') {
    # Do the memory-hog thing
    my $eol = $/;
    undef $/;
    $md5->add(<$fh>);
    $/ = $eol;
  } else {
    # It should just be a normal filehandle...
    $md5->addfile($fh);
  }
}

sub do_histogram {
    my ($aref) = @_;
    # Given an array of values, make a histogram

    my $lines = 20;		# # of histogram lines (not counting legend)
    my $width = 80;		# Maximum width
    my $bucket_format = '%1.5E'; # printf() format for bucket vals
    my $bucket_width = length(sprintf $bucket_format, 9.99999e102);
    my $numbuckets = int($width / ($bucket_width + 1));
    my @rc = ();
#print "bucket_width = $bucket_width\nnumbuckets = $numbuckets\n";

    my $nostar = sprintf '%*s ', -$bucket_width, ' ';
    my $star   = sprintf '%*s ', -$bucket_width, (' ' x int($bucket_width / 2).'*');
    @$aref = sort { $a <=> $b } @$aref;

    # Until we can put in Manas' clever bucket-determination scheme, just
    # make equal-size buckets for now.
    my $min = $aref->[0];
    my $max = $aref->[$#{$aref}];
    my $bucketsize = abs($max - $min) / $numbuckets;
    my $currmax = $min + $bucketsize;
#print "min = $min\nmax = $max\nbucketsize = $bucketsize\ncurrmax = $currmax\n";

    my $currbucket = 0;
    my $maxcount = 1;   # Protect against divide-by-zero when no samples are present
    my @buckets = ();
    foreach my $val (@$aref) {
	# Sort the values into buckets
	if ($val > $currmax) {
	    $currbucket++;
	    $currmax += $bucketsize;
	}
	$buckets[$currbucket]++;
	$maxcount = $buckets[$currbucket] if ($buckets[$currbucket] > $maxcount);
#print "currbucket = $currbucket\nmaxcount = $maxcount\n";
    }
    # Now normalize all the buckets to 1 - $lines
    my $factor = $lines / $maxcount;
    my $currline = '';
    for(my $i = $lines; $i; $i--) {
	for(my $j = 0; $j < $numbuckets; $j++) {
	    $currline .= ($buckets[$j] * $factor) >= $i ? $star : $nostar;
#print "currline = $currline\n";
	}
	push @rc, $currline;
	$currline = '';
    }
    for(my $j = 0; $j < $numbuckets; $j++) {
	$currline .= sprintf '%*s ', $bucket_width,
	             sprintf "$bucket_format ", $min + ($bucketsize * $j);
    }
    push @rc, $currline;
    $currline = '';
    for(my $j = 0; $j < $numbuckets; $j++) {
	$currline .= sprintf '%*s ', $bucket_width,
	             sprintf "$bucket_format ", $min + ($bucketsize * ($j + 1));
    }
    push @rc, $currline;
    $currline = '';
    for(my $j = 0; $j < $numbuckets; $j++) {
	$currline .= sprintf "%*s ", -$bucket_width, 'Count:';
    }
    push @rc, $currline;
    $currline = '';
    for(my $j = 0; $j < $numbuckets; $j++) {
	$currline .= sprintf "%*d ", -$bucket_width, $buckets[$j];
    }
    push @rc, $currline;

    return @rc;
}

sub format_error_line {
  my ($line, $line1, $line2, $pos, $opts) = @_;
  my $pospad = 7;
  if ($line > 9999) {
    # The _minimum_ width for the line number is 4 characters, but it
    # could be more, especially for binary compares where the "line number"
    # is actually the byte position in the file.
    $pospad = int(log($line) / log(10) + 4);
  }
  $pos++ unless $pos;
  if ($opts->{'binary'} &&
      length($line1) == 1 && length($line2) == 1) {
    my $val1 = sprintf("0x%02x", ord($line1));
    $val1 .= " ($line1)" if ($line1 =~ /[0-9A-Za-z]/);
    my $val2 = sprintf("0x%02x", ord($line2));
    $val2 .= " ($line2)" if ($line2 =~ /[0-9A-Za-z]/);
    return sprintf ("%04d:  %s\n%*s%s\n%*s",
		    $line, $val1,
		    $pospad, ' ', $val2,
		    ($pospad + 4), '^');
  } else {
    return sprintf ("%04d:  %s\n%*s%s\n%*s",
		    $line, $line1,
		    $pospad, ' ', $line2,
		    ($pospad + $pos), '^');
  }
}

1;
