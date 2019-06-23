#
# util.pl
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: util.pl 1899 2012-10-15 00:14:02Z CloyceS $

use strict;
use Safe;
use IO::Dir;
use File::Copy;
use File::Basename;
use File::Path;
use MIME::Base64;
use Digest::MD5;
use Carp;
use IO::Handle;
use IO::File;
use Fcntl qw(:flock);
use Scalar::Util qw(reftype blessed);
use LWP::UserAgent;
#use LWP::Debug qw(+);
use POSIX qw(:sys_wait_h);
use IO::Uncompress::Bunzip2 qw(:all);
use IO::Socket; # For PTD support
use Time::HiRes;
use Date::Parse;
use Data::Dumper;

require 'util_common.pl';

our ($ua);

my %logged_vars = ();
my %old_logged = ();
my $diff_debug = 0;

my $version = '$LastChangedRevision: 1899 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'util.pl'} = $version;

sub check_tolerances {
    my ($abstol, $reltol, $bench) = @_;
    my $ret = '';

    # Check reltol for large values
    if (reftype($reltol) eq 'HASH') {
      foreach my $val (get_hash_leaves($reltol)) {
        if ($val->[1] >= 1) {
          $ret .= "Unreasonably large relative tolerance ($val->[1]) set for $val->[0] in $bench\n";
        }
      }
    } else {
      if ($reltol >= 1) {
        $ret .= "Unreasonably large relative tolerance ($reltol) set for all in $bench\n";
      }
    }

    # Check abstol for small values
    # No, actually don't.  Absolute tolerances may really need to be very small.
    #if (reftype($abstol) eq 'ARRAY') {
    #} else {
    #  if ($abstol < epsilon) {
    #    $ret .= "Unreasonably small absolute tolerance ($abstol) set for all in $bench\n";
    #  }
    #}

    return $ret;
}

sub get_hash_leaves {
  my ($val, $curr) = @_;
  my @rc = ();

  if (reftype($val) eq 'HASH') {
    foreach my $key (sort keys %{$val}) {
      if ($curr ne '') {
        push @rc, get_hash_leaves($val->{$key}, $curr."->{$key}");
      } else {
        push @rc, get_hash_leaves($val->{$key}, $key);
      }
    }
  } elsif (reftype($val) eq 'ARRAY') {
    $curr = 'array' if $curr ne '';
    for(my $i = 0; $i < @{$val}; $i++) {
      push @rc, get_hash_leaves($val->[$i], $curr."->[$i]");
    }
  } else {
    return [ $curr, $val ];
  }

  return @rc;
}

sub copy_file {
    my ($source, $targetfile, $dirs, $verify, $sumhash) = @_;
    # CVT2DEV: $verify = 0;
    my $isbz2 = 0;  # Is the source file compressed?
    $sumhash = \%::file_md5 unless ref($sumhash) eq 'HASH';

    if (!defined($targetfile)) {
	$targetfile = basename($source);
    }
    if (ref($dirs) ne 'ARRAY') {
	if ($dirs eq '') {
	    $dirs = [ dirname($targetfile) ];
	    $targetfile = basename($targetfile);
	} else {
	    $dirs = [ $dirs ];
	}
    }

    # Do some pre-copy checks
    my $oldmode = 0644;
    foreach my $dir (@{$dirs}) {
        next unless defined($dir);
	my $target = jp($dir, $targetfile);
	if (-e $target) {
	    # Sheesh!  Make sure that the *target* isn't read-only
	    # Thanks very much, Microsoft!
	    $oldmode = (stat($target))[2];
	    $oldmode |= 0644;
	    chmod $oldmode, $target;
	}
    }

    # Copy the file into all the directories
    if ($source =~ s/\.bz2$//) {
	$isbz2 = 1;
	copy_bz2_file($source, $targetfile, $dirs, $verify, $sumhash);
    } else {
	foreach my $dir (@{$dirs}) {
            next unless defined($dir);
	    my $target = jp($dir, $targetfile);
	    if (!copy($source, $target)) {
		Log(0, "\nERROR: Copying $source to $target failed: $!\n");
		Log(0, "  in copy_file:\n".Carp::longmess()."\n\n");
		return 0;
	    }
	}
    }

    # Do the post-copy cleanup and file verification
    # Get the hash from the MANIFEST if the source is compressed (because
    # there's no real file to generate it _from_) or if check_integrity is
    # is on.
    my $refhash = $sumhash->{$source};
    if ($verify) {
	if (!defined($refhash)) {
	    # Okay, it's not in the existing set, so generate it
	    $refhash = md5filedigest(($isbz2) ? "${source}.bz2" : $source, $isbz2);
	}
    }
    foreach my $dir (@{$dirs}) {
        next unless defined($dir);
	my $target = jp($dir, $targetfile);
	# Ensure that the copied file is not read-only
	$oldmode = (stat($source))[2];
	$oldmode |= 0644;
	chmod $oldmode, $target;
	# Set the modification time on the target to match the source
	utime ((stat(_))[8,9], $target);

	if ($verify) {
	    my $targhash = md5filedigest($target);
	    Log(89, "Comparing MD5 hashes:\n  $refhash $source\n  $targhash $target\n");
	    my $errcount = 0;
	    while (($refhash ne $targhash) && ($errcount < 5)) {
		$errcount++;
		Log(0, "Target file ($target) hash doesn't match\nafter copy from $source in copy_file ($errcount tr".(($errcount > 1)?'ies':'y')." total)!\nSleeping 2 seconds to see if it gets better...\n");
		sleep(2);
		$targhash = md5filedigest($target);
	    }
	    if ($errcount >= 5) {
		# The files continued to mismatch; it's an error
		Log(0, "\nERROR: MD5 file mismatch while copying $source to $target\n");
		Log(0, "  in copy_file:\n".Carp::longmess()."\n\n");
                offer_verify_advice();
		# Let's leave some evidence for later diagnosis if keeptmp is
                # on, or if this is not a release build
                unlink $target unless ($::suite_version > 5 || istrue($::global_config->keeptmp));
		return 0;
	    }
	}
    }
    return 1;
}

sub copy_tree {
    my ($source, $target, $sumhash, $ignore, $fast) = @_;
    # CVT2DEV: $fast = 1;
    $sumhash = \%::file_md5 unless ref($sumhash) eq 'HASH';
    if (ref($ignore) eq 'ARRAY') {
	$ignore = { map { $_ => 1 } @{$ignore} };
    } elsif (ref($ignore) ne 'HASH') {
	$ignore = { };
    }
    my $dir = new IO::Dir $source;
    while (defined(my $file = $dir->read)) {
	next if $file eq '.' || $file eq '..';
	next if exists $ignore->{$file};
	my $sf = jp($source, $file);
        $file =~ s/\.bz2$//;
        my $tf = jp($target, $file);
        my $oldmode = 0644;
        if (-e $tf) {
            # Make sure that the target isn't read-only.  See bile above
            $oldmode = (stat($tf))[2];
	    $oldmode |= 0644;
	    chmod $oldmode, $tf;
        }
	if (-f $sf) {
	    if ($::check_integrity && !$fast) {
		if (!exists $sumhash->{$sf}) {
		    Log(0, "\n$sf has no stored checksum!\n");
                    offer_verify_advice();
		    return 0;
		}
		if ($sumhash->{$sf} ne md5filedigest($sf)) {
		    Log(0, "\n$sf is corrupt!\n");
                    offer_verify_advice();
		    return 0;
		}
	    }
            if ($sf =~ /\.bz2$/) {
              copy_bz2_file($sf, $file, [$target], 0);
            } else {
		if (!copy($sf, $tf)) {
		    Log(0, "ERROR: Copying $sf to $tf failed: $!\n");
		    Log(0, "  in copy_tree:\n".Carp::longmess());
		    return 0;
		}
            }
	    $oldmode = (stat($sf))[2];
	    # Ensure that the copied file is not read-only
	    $oldmode |= 0644;
	    chmod $oldmode, $tf;
	    utime ((stat(_))[8,9], $tf);
	} elsif (-d $sf && $file ne 'CVS' && $file ne '.svn') {
	    eval { mkpath($tf) };
            if ($@) {
                Log(0, "ERROR: Couldn't create destination directory: $@\n");
                return 0;
            }
	    copy_tree($sf, $tf, $sumhash, $ignore, $fast);
	}
    }
    return 1;
}

sub copy_bz2_file {
    my ($source, $destfile, $dirs, $verify, $sumhash) = @_;
    # CVT2DEV: $verify = 0;
    # Source file is compressed; dest file must be decompressed
    $sumhash = \%::file_md5 unless ref($sumhash) eq 'HASH';

    if (ref($dirs) ne 'ARRAY') {
	if ($dirs ne '') {
	    $dirs = [ $dirs ];
	} else {
	    $dirs = [ '' ];
	}
    }

    if ($source !~ /\.bz2$/) {
	$source .= '.bz2';
    }

    if ($::check_integrity && $verify) {
	# Check the MD5 sum of the compressed file; if it doesn't match,
	# what's the point of trying to decompress it?
        my $refhash = $sumhash->{$source};
	if (!defined($refhash)) {
	    Log(0, "No MD5 sum for $source; aborting bz2 copy\n");
            offer_verify_advice();
	    return 0;
	}
	my $filehash = md5filedigest($source);
	if ($refhash ne $filehash) {
	    Log(0, "ERROR: MD5 sum mismatch on compressed source file $source\n");
            offer_verify_advice();
	    return 0;
	}
    }

    # Trim the extension, if it's still there
    $destfile =~ s/\.bz2$//;

    # Get a copy of the destinations that we can munge
    my @dirs = @{$dirs};
    my $firstdest;
    for(my $i = 0; $i < @dirs; $i++) {
        if (defined($dirs[$i])) {
            $firstdest = jp($dirs[$i], $destfile);
            last;
        }
    }
    return 0 unless defined($firstdest);
    my $oldmode = 0644;
    if (-e $firstdest) {
	# Make sure that the destination isn't read-only
	$oldmode = (stat($firstdest))[2];
	chmod $oldmode|0644, $firstdest;
    }
    my $fh = new IO::File ">$firstdest";
    if (!defined($fh)) {
	Log(0, "Couldn't open \"$firstdest\" for writing: $!\n");
	return 0;
    }
    binmode $$fh, ':raw';

    # Read the source file a bit at a time.  In order to save memory, the
    # compressed file is read bit by bit and written out to the first
    # destination.  Then _that_ file is copied to the rest of the destinations.
    # Overall there's more I/O, but it should take less time than doing
    # multiple decompressions, and (more importantly) MUCH less memory than
    # reading the WHOLE thing into memory and just writing it multiple times.
    my $status = bunzip2 $source => $fh, 'Transparent' => 0;
    $fh->close();
    if (!$status) {
	Log(0, "Error decompressing \"$source\": $Bunzip2Error\n");
        unlink $firstdest;
	return 0;
    }
    $oldmode = (stat($source))[2];
    chmod $oldmode, $firstdest;
    utime ((stat(_))[8,9], $firstdest);

    # Now copy it into the list of directories
    my @written = $firstdest;
    foreach my $dir (@dirs) {
        next unless defined($dir);
	my $dest = jp($dir, $destfile);
        next if $dest eq $firstdest;
	if (-e $dest) {
	    # Make sure that the destination isn't read-only
	    $oldmode = (stat($dest))[2];
	    chmod $oldmode|0644, $dest;
	    unlink $dest;
	}
	if (!copy $firstdest, $dest) {
	    Log(0, "Copy from $firstdest to $dest failed: $!\n");
	    unlink @written;
	    unlink $dest;
	    return 0;
    	}
	push @written, $dest;
	# This should be unnecessary
	$oldmode = (stat($source))[2];
	chmod $oldmode, $dest;
	utime ((stat(_))[8,9], $dest);
    }
    return 1;
}

sub find_biggest_ext {	## find the file with the highest suffix
    my $dir = shift;
    my $ext = shift;
    $ext = '' unless defined($ext);
    my $dh = new IO::Dir $dir;
    my $num = 0;
    if (!defined $dh) {
	Log(0, "find_biggest_num: Can't open directory '$dir': $!\n");
    } else {
	while (defined($_ = $dh->read)) { 
	    $num = $1 if m/\.(\d+)${ext}$/ && $1 > $num;
	}
    }
    return $num;
}

sub build_tree_hash {
    my ($bmobj, $sumhash, @absdirs) = @_;
    my ($files, $dirs) = ({}, {});

    my $os = $bmobj->OS if (ref($bmobj) ne '');
    my @work;
    for my $dir (@absdirs) {
	push (@work, [$dir, '', ''])
    }

    while (@work) {
	my ($absdir, $absroot, @paths) = @{shift @work};
	while (@paths) {
	    my $path    = shift(@paths);
	    my $root    = jp($absroot, $path);
	    my $dir     = jp($absdir, $path);
	    my $dh = new IO::Dir $dir;
	    my $file;

	    if (! defined $dh ) {
		Log(0, "Can't open path '$dir: $!\n");
	        return(undef, undef);
	    }
	    while (defined($file = $dh->read)) {
		my $absfile = jp($dir, $file);
		my $relfile = jp($root, $file);
		if (-d $absfile) {
		    if ($file eq '.' || $file eq '..' || 
                        $file eq 'CVS' || $file eq '.svn') {
		    } elsif ($file =~ m/^OS_(.*)(-|$)/i) {
			if ($1 eq $os) {
			    push (@work, [ $absfile, $root, '' ]);
			}
		    } else {
			$dirs->{$relfile} = '';
			push (@paths, $relfile);
		    }
		} elsif (-f $absfile) {
		    if ($::check_integrity &&
                        istrue($bmobj->strict_rundir_verify) &&
			defined($sumhash) && ref($sumhash) eq 'HASH') {
			if (!exists($sumhash->{$absfile})) {
			    Log(0, "build_tree_hash: $absfile not found in MD5 sum list\n");
			    return (undef, undef);
			}
		    }
		    $files->{$relfile} = $absfile;
		} else {
		    Log(0, "build_tree_hash: Can't tell what $absfile is!\n");
		}
	    }
	}
    }
    return ($files, $dirs);
}

sub offer_verify_advice {
    if (!istrue($::global_config->reportable)) {
        Log(0, "\n Since this run is not reportable, you may avoid this error in the future\n");
        Log(0, " by setting\n");
        Log(0, "   strict_rundir_verify = 0\n");
        Log(0, " in your config file.\n\n");
    }
}

# Run a command and log the action
sub log_system {
    log_system_raw(1,@_);
}
sub log_system_noexpand {
    log_system_raw(0,@_);
}
sub log_system_raw {
    my ($expand, $cmd, $outn, $fake, $repl, $quiet, $no_output) = @_;
    ## $cmd   -- initially, the unexpanded command string; eventually the whole
    ## $outn  -- basename for output and errors files
    ## $repl  -- array of hash(es) of replacement variables and values
    ## $quiet -- Whether or not to complain about error exits
    ## $no_output -- Whether to suppress all output

    my $errname = "$outn.err";
    my $outname = "$outn.out";
    my $config  = $main::global_config;
    my $rc;
    my $desc;
    my $printcmd;
    my $env_vars = istrue($config->env_vars) && ($::lcsuite !~ /^cpu2/ || !istrue($config->reportable));
    my @repl = (reftype($repl) eq 'ARRAY') ? @{$repl} : ();
    my $teeout = $config->teeout eq 'dangerous' ? $config->teeout : istrue($config->teeout);
    if ($no_output) {
        $quiet = 1;
        $teeout = 0;
    }

    $desc = " $outn" if $outn ne '';

    if ($expand) {
        $cmd = ::path_protect($cmd);
        $cmd = command_expand($cmd, \@repl, 'no_log' => $no_output);
        $cmd = ::path_unprotect($cmd);
    }
    $printcmd = [ split (/[\r\n]+/, $cmd) ];

    my $fake_cmd = substr($cmd, 0, 40);
    $fake_cmd .= '...' if (length($fake_cmd) >= 40);

    if ($outn ne '') {
	$printcmd = redirect_cmd($cmd, $outname, $errname, $fake, $config);
	unlink $errname, $outname;
        $fake_cmd = "$outn ($fake_cmd)";
    }

    ## ready -- make a log entry if required
    Log (120, "Issuing$desc command '$cmd'\n") unless ($no_output || istrue($config->fake));

    ## give user some indication of what is happening if she is
    ## is about to get some tee output
    Log(0, join('; ', @{$printcmd})."\n") if (!$fake && ($teeout || $teeout eq 'dangerous'));

    my %oldENV = %ENV;
    main::munge_environment(@repl) if $env_vars;
    ## go -- this is it.. issue the command and grab the result
    my $start = time;
    Log (125, "Start$desc command: ", ctime($start), " ($start)\n") unless ($no_output || istrue($config->fake));
    my $loglvl = 180;
    my $errno = undef;
    $loglvl = 0 if ($teeout || $teeout eq 'dangerous' || istrue($config->fake));
    if ($fake) {
	Log(0, "$cmd\n") unless $no_output;
	$rc = 0;
    } else {
        if ($teeout ne 'dangerous' || $^O =~ /MSWin/) {
	  # If $config->fake is true, but $fake is not, then this is an example
	  # command (such as 'make -n') which should be sent to the screen
	  # as well as the log.
	  foreach my $subcmd (@{$printcmd}) {
	    $rc = system $subcmd;
            $errno = $! if $rc == -1;
	    last if $rc;
	  }
          Log($loglvl, "\n%% Fake commands from $fake_cmd:\n") if (!$no_output && istrue($config->fake));
	  # Log the contents of the output and errors files
	  Log($loglvl, "Command output:\n".join('', ::read_file($outname))."\n") if (!$no_output && -s $outname);
	  Log($loglvl, "Command errors:\n".join('', ::read_file($errname))."\n") if (!$no_output && -s $errname);
          Log($loglvl, "%% End of fake output from $fake_cmd\n\n") if (!$no_output && istrue($config->fake));
        } else {
          Log($loglvl, "\n%% Fake commands from $fake_cmd:\n") if (!$no_output && istrue($config->fake));
          # The only way to get here is to have teeout=dangerous
	  $rc = my_system(1, $outn, $outname, $errname, $cmd);
          $errno = $! if $rc == -1;
          Log($loglvl, "%% End of fake output from $fake_cmd\n\n") if (!$no_output && istrue($config->fake));
          # Sometimes this is polluted
          $? = $rc;
        }
    }
    my $stop = time;
    my $elapsed = $stop-$start;
    if (!$no_output && !istrue($config->fake)) {
      Log (125, "Stop$desc command: ", ctime($stop), " ($stop)\n");
      Log (125, "Elapsed time for$desc command: ", to_hms($elapsed), " ($elapsed)\n");
    }
    %ENV=%oldENV if $env_vars;

    if ($rc) { ## if there is a non-zero result from the $cmd
	if ($rc == $config->sigint && !istrue($config->ignore_sigint)) {
	    ## the command was interrupted
	    Log(0, "Exit on SIGINT\n"); 
	    do_exit(1);
	}

	my $msg = '';
        my $files = 0;
        my $filename = jp(cwd(), $errname);
        if ($errname ne '' && -f $filename && -s $filename) {
          $msg = "'$filename'";
          $files++;
        }
        if ($^O =~ /MSWin/ || $files == 0) {
          # Windows compilers often dump the important error messages to
          # stdout.
          my $filename = jp(cwd(), $outname);
          if ($outname ne '' && -f $filename && -s $filename) {
            $files++;
            if ($msg ne '') {
              $msg = "$msg and '$filename'";
            } else {
              $msg = "'$filename'";
            }
          }
        }
        if ($files > 0) {
          if ($files > 1) {
            $msg = ': check files '.$msg;
          } else {
            $msg = ': check file '.$msg;
          }
        } else {
          $msg = '; no non-empty output files exist';
        }
        $msg .= "\n";

        my $exitcode = WEXITSTATUS($rc);
        $msg .= "  Command returned exit code $exitcode\n" if $exitcode;
        if ($rc & 0xff) {
          $msg .= sprintf "  Command exited with signal %d%s\n", $rc & 0x7f, ($rc & 0x80) ? '(core dumped)' : '';
        }
        $msg .= "  Error may have been \"$errno\"\n" if defined($errno);

	Log(0, "Error with$desc '$cmd'$msg") unless $quiet;
    }
    return $rc;
}

sub munge_environment {
    my (@refs) = @_;
    no strict 'refs';

    while (@refs && ref($refs[0]) ne '') {
	my $ref = shift @refs;
	if (blessed($ref) && $ref->isa('Spec::Config')) {
	    foreach my $key ($ref->list_keys) {
                if ($key =~ m/^ENV_(\S+)/) {
                    my $name = $1;
                    my $val = $ref->accessor($key);
                    Log(35, "Setting(config) environment variable \"$name\" to \"$val\"\n");
                    if ($val =~ /\s+$/) {
                        Log(0, "WARNING: Value for environment variable \"$name\" has trailing whitespace!\n");
                    }
                    $ENV{$name} = $val;
                }
	    }
	} elsif (reftype($ref) eq 'HASH') {
	    foreach my $key (keys %$ref) {
                if ($key =~ m/^ENV_(\S+)/) {
                    my $name = $1;
                    my $val = $ref->{$key};
                    Log(35, "Setting(hash) environment variable \"$name\" to \"$val\"\n");
                    if ($val =~ /\s+$/) {
                        Log(0, "WARNING: Value for environment variable \"$name\" has trailing whitespace!\n");
                    }
                    $ENV{$name} = $val;
                }
	    }
	}
    }
    while (@refs > 1) {
	my $name = shift @refs;
	my $val = shift @refs;
        if ($name =~ m/^ENV_(\S+)/) {
            Log(35, "Setting(param) environment variable \"$name\" to \"$val\"\n");
            if ($val =~ /\s+$/) {
                Log(0, "WARNING: Value for environment variable \"$name\" has trailing whitespace!\n");
            }
            $ENV{$name} = $val;
        }
    }
}

sub command_expand {
    my ($pattern, $repl, %opts) = @_;

    # If the string does not contain any $, then there will not be anything
    # to expand.  But if the verbosity is sufficiently high, do it anyway.
    return $pattern unless $pattern =~ m/\$/ || $::global_config->verbose >= 35;

    my $last_string;
    my $do_log = 1 - !!$opts{'no_log'};  # Intentional; undef => 0
    my $do_setup = 1;
    my @refs = ();
    if ((::reftype($repl) eq 'ARRAY')) {
        @refs = @{$repl};
    } else {
        @refs = ($repl);
    }
    my $s = $opts{'safe'};
    if (defined($s)) {
        if (ref($s) eq 'Safe') {
            # The caller has provided a presumably pre-setup Safe compartment
            # with variables, etc, populated.
            $do_setup = 0;
        }
    }
    $s = new_safe_compartment('tmp') unless defined($s);

    my $string = $pattern;
    my %paths = ();		# Path variables that may need
				# post-interpolation fixup if they contain \

    no strict 'refs';

    if ($do_setup) {
        my (undef, $file, $line) = caller;

        if ($do_log) {
            %old_logged = %logged_vars;
            %logged_vars = ('__called_from_sub__' => "$file line $line");
        }
        while (@refs && ref($refs[0]) ne '') {
            my $ref = shift @refs;
            if (blessed($ref) && $ref->isa('Spec::Config')) {
                for my $key ($ref->list_keys) {
                    my $val = $ref->accessor($key);
                    safe_store($key, $val, $s, 'config', \%paths, $do_log);
                }
            } elsif (ref($ref) eq 'HASH') {
                for my $key (keys %$ref) {
                    my $val = $ref->{$key};
                    safe_store($key, $val, $s, 'hash', \%paths, $do_log);
                }
            }
        }
        # These are expanded by specinvoke
        my $safevarref = $s->varglob('SPECCOPYNUM');
        $$safevarref = '$SPECCOPYNUM';
        $safevarref = $s->varglob('BIND');
        $$safevarref = '$BIND';
        report_sub_vars() if $do_log;
    }

    $string = $pattern;
    for (my $i = 0; ; $i++) {
	$last_string = $string;
	$string =~ s/([\\])(.)/($2 eq '#')?"\\$1$2":"\\$1\\$2"/eg;
	$string =~ s/\#/\\\#/g;
	$string = $s->reval("qq#$string#;");
	if ($@) {
            Log(0, "expansion of '$pattern' in stage '$last_string' caused an eval error: $@\n");
            do_exit(1);
        }
	last if $string eq $last_string;
	if ($i >= 100) {
            Log(0, "expansion of '$pattern' resulted in $i recursions!\n");
            do_exit(1);
        }
    } 
    $string =~ s/([\\])(\#)/($2 eq '#')?"\\$1$2":"\\$1\\$2"/eg;
    $string =~ s/\#/\\\#/g;
    $string = $s->reval("qq#$string#;");
    # Now that all of the interpolations have happened, go back and make the
    # paths right.
    # We reverse sort by length of path to avoid screwing up more specific
    # paths by replacing their prefixes first.
    foreach my $pathkey (sort {	length($paths{$b}->[1]) <=> length($paths{$a}->[1]) } keys %paths) {
	$string =~ s/$paths{$pathkey}->[0]/$paths{$pathkey}->[1]/g;
    }

    return wantarray ? ($string, $s) : $string;
}

sub safe_store {
    my ($key, $val, $compartment, $label, $pathref, $do_log) = @_;

    my $valtype = ref($val);
    # Only put scalars and arrays into the Safe compartment.
    return if ($valtype ne '' && $valtype ne 'ARRAY');

    # Some variables should not be put into the Safe compartment.
    return if ($key =~ /^(?:(?:raw|pp)txtconfig(?:all)?|oldmd5|compile_options|flags)$/);

    my $safevarref = $compartment->varglob($key);
    if ($valtype eq 'ARRAY') {
	# There are a few arrays that should not be propagated
	return if ($key =~ /^(?:refs|formatlist|benchconf|benchsets|result_list|entries|runlist|setobjs|orig_argv)/);
	@{$safevarref} = @{$val};
        $logged_vars{$key} = [ '( '.join(', ', @{$val}).' )', $key, $label, '@' ] if $do_log;
    } else {
	$$safevarref = $val;
        $logged_vars{$key} = [ "\"$val\"", $key, $label, '$' ] if $do_log;
	if ($key =~ /(\S*(?:path|top))/o) {
	    # Transform any backslashes in the path to forward
	    # slashes, and stow the original result so that it
	    # can be put back after the eval (which would destroy
	    # the backslashes in the path)
	    my $fixpath = $val;
	    $fixpath =~ s/\\/\//go;
	    $pathref->{$key} = [ $fixpath, $val ];
	    $$safevarref = $fixpath;
	}
    }
}

sub report_sub_vars {
    my $header_done = 0;
    my $min_log_level = 35;

    Log($min_log_level, "Variable list for substitution");
    if (exists($logged_vars{'__called_from_sub__'})) {
      Log($min_log_level, " (called from $logged_vars{'__called_from_sub__'})");
    }
    Log($min_log_level, ":\n");

    # Now report on what's changed
    my %seen = ();
    foreach my $key (sort grep { exists($old_logged{$_}) } keys %logged_vars) {
      next if $key eq '__called_from_sub__';
      my ($oldtxt) = @{$old_logged{$key}};
      delete $old_logged{$key};
      $seen{$key}++;
      my ($txt, $item, $from, $type) = @{$logged_vars{$key}};
      next if $oldtxt eq $txt;
      if (!$header_done) {
        Log($min_log_level, " - Variables available for interpolation that have changed since the last list:\n");
        $header_done = 1;
      }
      Log($min_log_level, "    (From $from) $type$item = $txt\n");
    }
    if (!$header_done) {
      Log($min_log_level, " - No variables changed\n");
    }

    # Now for the new stuff.
    $header_done = 0;
    foreach my $key (sort grep { !exists($seen{$_}) } keys %logged_vars) {
      next if $key eq '__called_from_sub__';
      my ($txt, $item, $from, $type) = @{$logged_vars{$key}};
      if (!$header_done) {
        Log($min_log_level, " - Variables available for interpolation that were not in the last list:\n");
        $header_done = 1;
      }
      Log($min_log_level, "    (From $from) $type$item = $txt\n");
    }
    if (!$header_done) {
      Log($min_log_level, " - No new variables\n");
    }

    # Now for the deleted stuff.
    $header_done = 0;
    foreach my $key (sort keys %old_logged) {
      next if $key eq '__called_from_sub__';
      my ($txt, $item, $from, $type) = @{$old_logged{$key}};
      if (!$header_done) {
        Log($min_log_level, " - Variables from the previous list that are NO LONGER AVAILABLE:\n");
        $header_done = 1;
      }
      Log($min_log_level, "    $type$item\n");
    }
    if (!$header_done) {
      Log($min_log_level, " - No deleted variables\n");
    }
}

# Munge the command to redirect the output correctly for the OS
# also handle teeout
sub redirect_cmd {
    my ($cmd, $out, $err, $fake, $config) = @_;

    # Split the $cmd string on CR or LF because it's important that *all*
    # of the commands have the redirection applied to them.
    my @cmds = split(/[\r\n]+/, $cmd);

    if ((!defined($out) || $out eq '') &&
        (!defined($err) || $err eq '')) {
      return \@cmds;
    }

    if (istrue($config->teeout)) {
      if ($^O =~ /MSWin/ || !($fake || istrue($config->fake))) {
	# Windows doesn't have tee(1); treat it as a normal output and let
	# log_system_raw dump the output files to the log and screen after
	# it's run.
        # For other systems not using the "dangerous" teeout, avoid the use
        # of tee(1) as it masks return values.
	$cmd = [ shift(@cmds)." > $out 2> $err" ];
	push @{$cmd}, map { "$_  >> $out 2>> $err" } @cmds if (@cmds+0);
      } else {
	  $cmd = [ shift(@cmds)." 2> $err | tee $out" ];
	  push @{$cmd}, map { "$_  2>> $err | tee -a $out" } @cmds if (@cmds+0);
      }
    } else {
      $cmd = [ shift(@cmds)." > $out 2> $err" ];
      push @{$cmd}, map { "$_  >> $out 2>> $err" } @cmds if (@cmds+0);
    }
    return $cmd;
}

## ############
## SUB                   FROM_HMS
## ############

## takes strings of hh:mm:ss (or mm:ss) and returns number of seconds

sub from_hms {
    my ($time) = @_;
    my (@vals) = split (":", $time);
    $time = 0;
    for (@vals) {
        $time *= 60;
        $time += $_;
    }
    $time;
}

## ############
## SUB                   TO_HMS
## ############

## takes seconds and returns a string of hh:mm:ss
## optionally can take a second argument of decimal seconds

sub to_hms {
    my ($t, $t2) = @_;
    my ($h,$m,$s);
    $s = $t % 60;
    $t = int($t/60);
    $m = $t % 60;
    $h = int($t/60);
    if ($t2) {
	sprintf ("%02d:%02d:%02d.%06d", $h, $m, $s, $t2);
    } else {
	sprintf ("%02d:%02d:%02d", $h, $m, $s);
    }
}

sub uniq {
    my (@data) = @_;
    my %u = map { $_ => 1 } @data;
    return keys %u;
}

sub apply_diff {
    my ($path, $hunks) = @_;
    my ($all_ok, $offset_used) = (1, 0);

    my $fh = new IO::File '<'.$path;
    die "Couldn't open $path for reading: $!\nStopped" unless defined($fh);

    # This will take more memory (two copies of each file instead of just one),
    # but is pretty necessary to ensure that we have arrays of lines no matter
    # which OS happens to be running the script.
    local $/ = undef;		# Slurp mode
    my $contents = <$fh>;
    undef $fh;

    # Clean the line endings.
    # Don't use [\r\n]+ for the split because that removes sequences of
    # blank lines.
    my @oldfile = map { tr{\012\015}{\012\012}s; $_ } split(/(?:\n|\r\n)/, $contents);

    # The basic workings are from apply_diff in Algorithm::Apply::Diff

    my $delta = 0;
    my $hunk_count = 0;
    foreach my $changeref (@{$hunks}) {
	$hunk_count++;
        if ($diff_debug) {
            Log(0, "\n\n---------------------------------------------------------------\n");
            Log(0, "New hunk (#$hunk_count): base = ".$changeref->{'base'}."; context = ".$changeref->{'clines'}."\n");
            Log(0, "Current delta is $delta\n");
            Log(0, "\nCalling match_context($changeref->{'base'} + $delta, $changeref->{'context'}, \@oldfile)\n");
        }
	my $base = match_context($changeref->{'base'} + $delta,
			     $changeref->{'context'}, \@oldfile);
	my $offset = $base - ($changeref->{'base'} + $delta);
        Log(0, "base == $base\noffset == $offset\n") if $diff_debug;
	if (!defined($base)) {
	    Log(0, "ERROR: hunk $hunk_count FAILED at $changeref->{'base'} for $path\n");
	    $all_ok = 0;
	    next;
	}
	$offset_used++ if $offset;

	# The context finder effectively gets rid of any "delta" that we
	# might need to keep track of.  It would always be 0 if you could
	# ensure that the original file was the same as the file against
	# which the diff was generated.  But if you could guarantee that,
	# all of this context crap wouldn't be necessary.
	$delta -= ($base - $changeref->{'base'});	# Probably 0
        Log(0, "(context adj) delta == $delta\n") if $diff_debug;

	# Because finding the context effectively changes the offset into
	# the "new" file, it's necessary to adjust the index for new insertions
	# to take into account the "help" that we got from the context finder.
	my $newdelta = $changeref->{'base'} - $base + $offset;
        Log(0, "newdelta == $newdelta\n") if $diff_debug;
	foreach my $change (@{$changeref->{'diffs'}}) {
	    if (ref($change) eq 'ARRAY') {
		my ($pos, $line, $repl) = @{$change};
                my $del_line = $repl + $base + $delta + $offset;
		if (defined($repl)) {
		    # Do the removal
		    my @oldlines = splice(@oldfile, $del_line, 1);
                    Log(0, "Removed line at ($repl + $base + $delta + $offset = $del_line):\n  ".join("\n  ", @oldlines)."\n") if $diff_debug;
		    --$delta;	# Because it will be incremented again shortly
		}
		# Do the add
		splice(@oldfile, $pos + $base + $newdelta, 0, $line);
                Log(0, "Added line at ($pos + $base + $newdelta = ".($pos + $base + $newdelta).") (delta == $delta):\n  $line\n") if $diff_debug;
		++$delta;
	    } elsif (ref($change) eq '' && ($change <= 0)) {
		# It's a delete
                my $del_line = (-1 * $change) + $base + $delta + $offset;
                if ($del_line <= $#oldfile) {
                    my @oldlines = splice(@oldfile, $del_line, 1);
                    Log(0, "Deleted lines at ((-1 * $change) + $base + $delta + $offset = $del_line):\n  ".join("\n  ", @oldlines)."\n") if $diff_debug;
                    --$delta;
                } elsif ($diff_debug) {
                    Log(0, "Can't delete line $del_line of ".$#oldfile.": out of range\n");
                }
	    } else {
		die "Huh?  Bad diff ($change)\n";
	    }
	}
	$delta += ($base - $changeref->{'base'});	# Probably 0
        if ($diff_debug) {
            Log(0, "(context REadj) delta == $delta\n");
            print_range(0, \@oldfile, "Finished hunk:\n  ", "\n  ", ($changeref->{'base'} - 5), ($changeref->{'base'} + 10)); Log(0, "\n");
            Log(0, "(post apply) delta == $delta\n");
        }
	if ($offset) {
	    Log(125, "    hunk $hunk_count offset ".pluralize($offset, 'line')." for $path\n");
	} else {
            Log(125, "    hunk $hunk_count applied cleanly to $path\n");
	}
    }

    # Rewrite the file now that it has been transformed into its new form...
    $fh = new IO::File '>'.$path;
    $fh->print(join("\012", map { defined($_) ? $_ : "HEY! UNDEF LINE!" } @oldfile)."\012");
    $fh->close();

    return (md5diffdigest($path), $offset_used, $all_ok);
}

sub match_context {
    my ($base, $context, $lines) = @_;
    my $rc = undef;

    # Find and return the index into @$lines where all of @$context can be
    # found.  Return undef if not found.

    return undef if (ref($context) ne 'ARRAY' || ref($lines) ne 'ARRAY');

    $rc = search_context($base, 1, $context, $lines);
    $rc = search_context($base, -1, $context, $lines) if (!defined($rc));

    return $rc;
}

sub search_context {
    my ($base, $inc, $context, $lines) = @_;
    # This actually does the work that you thought match_context would do

    if ($diff_debug) {
        Log(0, "search_context($base, $inc, $context, $lines) called\n");
        print_range(0, $context, "Context:\n  ", "\n  "); Log(0, "\n");
        print_range(0, $lines, "Lines[$base..]:\n  ", "\n  ", $base, $base + $#{$context}); Log(0, "\n");
    }

    for(; $base < @{$lines}+0 && $base >= 0; $base += $inc) {
	my $idx = 0;
	while(defined($lines->[$base + $idx]) && defined($context->[$idx]) &&
	      ($lines->[$base + $idx] eq $context->[$idx])) {
	    $idx++;
	}
	if ($idx >= @{$context}+0) {
	    # Finished!
            Log(0, "Found at $base\n") if $diff_debug;
	    return $base;
	}
    }
    Log(0, "Not found\n") if $diff_debug;
    return undef;
}

sub print_range {
    my ($loglevel, $aref, $head, $eol, $start, $end) = @_;
    $start = 0 unless defined $start;
    $end = $#{$aref} unless defined $end;
    Log($loglevel, $head) if defined($head);
    $eol = "\n" unless defined($eol) && $eol ne '';
    while($start < 0) {
        Log($loglevel, sprintf("%05d: undef$eol", $start));
        $start++;
    }
    while($start < $end) {
        if ($start <= $#{$aref}) {
            Log($loglevel, sprintf("%05d: %s$eol", $start, defined($aref->[$start]) ? $aref->[$start] : 'undef'));
            $start++;
        } else {
            Log($loglevel, sprintf("%05d: *** out of range ***$eol", $start, ));
            $start++;
        }
    }
}

sub check_version {
    # Phone home (to SPEC) to see if a newer version of the suite has been
    # released.
    my ($url, $timeout, $proxy, $will_continue) = @_;
    my ($ver, $date, $pause) = (undef, undef, 0);
    $url = $::default_config->{'version_url'} unless defined($url);
    $timeout ||= 30;

    Log(1, "Loading \"$url\" for version check: ");
    my $res = ::get_url(\$ua, $url);
    if ($res->is_success) {
        Log(1, "OK\n");
        ($ver, $date) = split(/\s+/, $res->content);
        my $suitever = $::suite_version;
        $suitever /= 1000 if $suitever > 4; # Deal with pre-release
        if ($ver < $suitever) {
            Log(0, "\n".
                   "WARNING: You are running a version of the suite that is newer than the newest\n".
                   "         official release from SPEC.  Generated results may not be acceptable\n".
                   "         for publication.\n".
                   "\n");
            $pause = 1;
        } elsif ($ver > $suitever) {
            Log(0, "\nNOTICE: There is a newer version of the suite available from SPEC.\n  Version $ver was released on ".scalar(CORE::localtime($date))."\n\n");
            $pause = 1;
        }
    } else {
        Log(1, "failed\n");
        Log(0, "\nNotice: Suite version checking failed; got\n  ".$res->status_line."\n\n");
        Log(0, "          A connection to the internet is useful, but is NOT required\n"); 
        Log(0, "          in order to run $::suite.  If one is available, several\n");
        Log(0, "          components will be checked to see if they are current.  If\n");
        Log(0, "          you need to use an HTTP proxy to access the Internet, please\n");
        Log(0, "          see the 'http_proxy' entry in config.html.\n\n");
        $pause = 1;
    }
    if ($pause && $will_continue) {
        my $spaces = " " x 23;
        Log(0, "${spaces}----------------------------------\n");
        Log(0, "${spaces}The run will continue in 5 seconds\n");
        Log(0, "${spaces}----------------------------------\n\n");
        sleep 5;
    }

    return($ver, $date);
}

sub generate_runspec_commandline {
    my ($cl_opts, $config, $macros, $unmacros, @options) = @_;

    my @command = (jp($config->top, 'bin', 'specperl'), jp($config->top, 'bin', 'runspec'), '--config', $config->config);

    # Do macro definitions
    foreach my $macro (sort keys %{$macros}) {
        push @command, '--define', $macro.'='.$macros->{$macro};
    }
    foreach my $macro (sort keys %{$unmacros}) {
        push @command, '--undef', $macro;
    }

    foreach my $thing (qw(keeptmp log_timestamp)) {
        if (istrue($config->accessor_nowarn($thing))) {
            push @command, "--$thing";
        } else {
            push @command, "--no$thing";
        }
    }

    push @command, @options;

    return wantarray ? @command : join(' ', @command);
}

sub list_dir {
    my ($dir, %opts) = @_;
    my @rc = ();

    if (!-d $dir) {
        if (!-e $dir) {
            return "*** Directory \"$dir\" does not exist! ***\n";
        } else {
            return "*** \"$dir\" is not a directory! ***\n";
        }
    }

    my $dh = new IO::Dir $dir;
    if (!defined($dh)) {
        return "*** \"$dir\" could not be opened for reading: $!\n";
    }
    while(defined(my $file = $dh->read)) {
        if ($opts{'stat'}) {
            push @rc, "$file (stat: ".join(',', stat(::jp($dir, $file))).')';
        } else {
            push @rc, $file;
        }
    }

    return @rc;
}

# Munge up a path so that backslashes can be preserved and path separators
# normalized.
sub path_protect {
    my ($text, $as_win) = @_;
    $as_win = ($^O =~ /MSWin/) unless defined($as_win);

    # Here's the special character breakdown:
    # 0377 - path separator (to be converted to native separator)
    # 0376 - literal forward slash

    if ($as_win) {
	# On Windows, assume that whitespace-slash-nonslash_text is a switch
	# and leave it alone.  "/.../" is a path, and those should be munged.
	# All non-doubled backslashes are path components, so munge those too
	
	# First, doubled backslashes in a network path
	$text =~ s#(?<=\s)\\\\(\S+[\\/])#\377\377$1#g;
	$text =~ s#^\\\\(\S+[\\/])#\377\377$1#g;

	# Then all the other backslashes (path separators)
	$text =~ s/\\/\377/g;

	# Leading forward slashes (path separators)
	$text =~ s#(?<=\s)/(\S+/)#\377$1#g;

	# Embedded forward slashes (path separators)
	$text =~ s#(?<!\s)/#\377#g;

	# Other forward slashes (switch character)
	$text =~ s#/#\376#g;
    } else {
	# Easy... / is a path separator (ONLY), and \ is an escape (ONLY)

	# Forward slashes (path separators)
	$text =~ s#/#\377#g;
    }

    return $text;
}

sub path_unprotect {
    my ($text, $as_win) = @_;
    $as_win = ($^O =~ /MSWin/) unless defined($as_win);

    $text =~ s#\376#/#g;
    if ($as_win) {
	# Then all the other backslashes (path separators)
	$text =~ s/\377/\\/g;
    } else {
	$text =~ s#\377#/#g;
    }
    return $text;
}

sub check_list {
  # Check to see if $item appears in the text of $list.  For some reason,
  # $list =~ /$item/ does not always work...
  my ($list, $item) = @_;

  foreach my $listitem (split(/[,[:space:]]+/, $list)) {
    return 1 if ($listitem eq $item);
  }
  return 0;
}

sub send_to_meters {
  my ($cmd, @meterlist) = @_;

  # For multiple meters, this would best be done in parallel, but in Perl
  # that's tough to do in a portable fashion.
  foreach my $meter (@meterlist) {
    $meter->{'sock'}->print($cmd);
  }

  # XXX Error return should be possible
  return 1;
}

sub get_meter_responses {
  my ($cmd, $meters, $expected) = @_;
  $meters = ref($meters) eq 'ARRAY' ? $meters : [ $meters ];

  foreach my $meter (@{$meters}) {
    my $tmp = '';
    do {
      $tmp = $meter->{'sock'}->getline();
      $tmp =~ tr/\015\012//d;
      ::Log(134, "Meter '".$meter->{'name'}."' returns '$tmp' for '$cmd' command\n");
      push @{$meter->{'responses'}}, $tmp;
    } while (defined($expected) && $tmp !~ /$expected/);
  }

  # XXX Error return should be possible
  return 1;
}

# Return a meter-specific range value if one is present, the default if one
# is set, or undef otherwise.
sub per_meter_range {
    my ($meter, $ranges) = @_;

    return undef if (ref($meter) ne 'HASH' || !defined($ranges));

    if (ref($ranges) eq 'HASH') {
        my $name = $meter->{'name'};
        if (exists($ranges->{"$name"}) && $ranges->{"$name"} =~ /^[.\d]+/) {
            return $ranges->{"$name"};
        } elsif (exists($ranges->{'default'}) && $ranges->{'default'} =~ /^[.\d]+/) {
            return $ranges->{'default'};
        }
    } elsif ($ranges =~ /^[.\d]+/) {
        # No per-meter settings
        return $ranges;
    }

    return undef;
}

# Given a hash with ranges and a meter reference, set those ranges if possible,
# returning 1 on success and 0 otherwise.
sub meter_read_range {
    my ($meter, $channel) = @_;

    # Nothing to do if the meterref isn't a meter
    return undef if (ref($meter) ne 'HASH');

    my $sock = $meter->{'sock'};
    my $name = $meter->{'name'};
    my $chanselect = ($channel eq '') ? '' : ",$channel";
    my $cmd = "RR$chanselect";
    ::Log(34, "PTD($name): Sending range reading command '$cmd'".($channel eq '' ? '' : " for channel $channel")."\n");
    $sock->print("$cmd\r\n");
    my $tmp = $sock->getline();
    $tmp =~ tr/\015\012//d;
    ::Log(34, "PTD($name): Got response '$tmp'\n");
    if ($tmp =~ /^Invalid number of parameter/) {
        ::Log(0, "ERROR: PTD at $name rejects command '$cmd'\n");
        return undef;
    } elsif ($tmp !~ /^Ranges,/) {
        ::Log(0, "ERROR: Unkown response '$tmp' received when trying to read ranges on PTD at $name\n");
        return undef;
    } else {
        my @resp = split(/,/, $tmp);
        return { 'a_auto' => $resp[1], 'a' => $resp[2],
                 'v_auto' => $resp[3], 'v' => $resp[4] };
    }
}

# Given a hash with ranges and a meter reference, set those ranges if possible,
# returning 1 on success and 0 otherwise.
sub meter_set_range {
    my ($meter, $ranges) = @_;

    # Nothing to do if the meterref isn't a meter or if the ranges
    # don't contain ranges...
    return 1 if (ref($meter) ne 'HASH' || ref($ranges) ne 'HASH');

    if ($meter->{'can_rangeset'}) {
        my ($name, $sock) = @{$meter}{'name', 'sock'};
        foreach my $rangetype (qw(a v)) {
            my $tmprange = per_meter_range($meter, $ranges->{$rangetype});
            if (defined($tmprange) && $tmprange > 0) {
                for(my $chan = 0; $chan < $meter->{'channels'}; $chan++) {
                    my $chanselect = ($chan == 0) ? '' : ",$chan";

                    # Read the current range to see if we even need to try
                    # to set the range for this channel
                    if ($chan > 0 || $meter->{'channels'} == 1) {
                        my $currange = meter_read_range($meter, ($chan == 0 ? '' : $chan));
                        if (!defined($currange) || ref($currange) ne 'HASH') {
                            # meter_read_range will have already logged the error message
                            return 0;
                        } elsif ($currange->{$rangetype.'_auto'} <= 0 && $currange->{$rangetype} == $tmprange) {
                            ::Log(34, "PTD($name): '$rangetype' range".($chanselect ne '' ? " for channel $chan" : '')." already set\n");
                            next;
                        }
                    }

                    my $cmd = "SR,$rangetype,$tmprange$chanselect";
                    ::Log(34, "PTD($name): Sending range setting command '$cmd' for channel $chan\n");
                    $sock->print("$cmd\r\n");
                    my $tmp = $sock->getline();
                    $tmp =~ tr/\015\012//d;
                    ::Log(34, "PTD($name): Got response '$tmp'\n");
                    if ($tmp =~ /^(?:Null channel|Invalid channel|Channel number out)/) {
                        ::Log(0, "ERROR: Bad channel while setting '$rangetype' range on PTD at $name with command '$cmd': $tmp\n");
                        return 0;
                    } elsif ($tmp =~ /^(?:Error in|Invalid number of) parameter/) {
                        ::Log(0, "ERROR: PTD at $name rejects command '$cmd'\n");
                        return 0;
                    } elsif ($tmp =~ /^(?:Error|Meter busy)/) {
                        ::Log(0, "ERROR: Failed trying to set '$rangetype' range on PTD at $name\n");
                        return 0;
                    } elsif ($tmp !~ /^Range $rangetype changed/i) {
                        ::Log(0, "WARNING: Unknown response '$tmp' received when trying to set '$rangetype' range on PTD at $name\n");
                    }

                    # Read the range back and make sure it's set properly
                    # (except for the sum channel on multi-channel analyzers)
                    if ($chan > 0 || $meter->{'channels'} == 1) {
                        my $currange = meter_read_range($meter, ($chan == 0 ? '' : $chan));
                        if (!defined($currange) || ref($currange) ne 'HASH') {
                            # meter_read_range will have already logged the error message
                            return 0;
                        } elsif ($currange->{$rangetype.'_auto'} > 0 || $currange->{$rangetype} != $tmprange) {
                            ::Log(0, "ERROR: '$rangetype' range received from PTD at $name does not match range set ($tmprange)\n");
                            return 0;
                        }
                    }
                }
            }
        }
    }

    return 1;
}

# Given a list of meters (host:port or host), connect to them and
# return a list of sockets as well as initial responses.
sub meter_connect {
  my ($meterlist, $timeout, $ranges) = @_;
  my @rc = ();
  my $sock;

  return undef unless ref($meterlist) eq 'ARRAY';

  my $have_alarm = eval { alarm(0); 1 };
  # As of 6 Jan 2012, alarm() does not work in the way we want it to
  # on Windows 7 with Perl 5.12.3.  So just pretend Windows doesn't
  # support it:
  $have_alarm = 0 if ($^O =~ /Win32/);

  # For multiple meters, this would best be done in parallel, but in Perl
  # that's tough to do in a portable fashion.
  foreach my $meter (@{$meterlist}) {
    next unless (defined($meter) && $meter ne '');
    my ($host, $port) = ($meter, 8888);
    if ($meter =~ m#^([^:]+)(?::(\d+))?$#) {
      # Not a full URI, just a host:port pair
      $host = $1;
      $port = $2 if ($2 ne '')
    } else {
      ::Log(0, "ERROR: '$meter' is not a valid meter\n  specification. Use either a hostname or host:port notation.\n");
      $sock = -1;
      next;
    }

    # If an error's been seen, don't try to connect to more meters
    next if $sock == -1;
    
    my $timeout_msg = $have_alarm ? "with $timeout second timeout" : "(no timeout)";
    # The newline is necessary to get it to output immediately
    ::Log(103, "Attempting to connect to PTD at $host:$port $timeout_msg...\n");
    eval {
      # All this "alarm" business is because IO::Socket::INET's Timeout
      # doesn't actually do anything.
      local $SIG{'ALRM'} = sub { die 'connect timeout' };
      alarm $timeout if $have_alarm;
      $sock = new IO::Socket::INET(Proto => 'tcp',
                                   PeerAddr => $host,
                                   PeerPort => $port,
                                   Timeout => $timeout);
      alarm 0 if $have_alarm;
    };
    if (defined($sock)) {
      ::Log(134, "  Successfully connected to $host:$port\n");
    } else {
      if ($@ && $@ =~ /connect timeout/) {
        ::Log(103, "  Connection to $host:$port timed out!\n");
      } elsif ($@) {
        ::Log(103, "  Connection to $host:$port failed (eval returned '$@')\n");
      } else {
        ::Log(103, "  Connection to $host:$port failed!\n");
      }
      $sock = -1;
      last;
    }

    my $meterref = {
                     'name' => $host.':'.$port,
                     'tag'  => lc($host.$port),     # will be fixed up more
                     'sock' => $sock
                   };
    $meterref->{'tag'} =~ tr{A-Za-z0-9}{}cd;

    # Ask PTD about the meter that's attached
    $sock->print("Identify\r\n");
    # From a now-vanished section of the PTD design document, the output is
    # expected to be the following, delimited by commas:
    # meter driver module + driver IDN response
    # averaging interval in ms
    # can measure watts / temperature?
    # can measure volts / humidity?
    # can measure amps?
    # can measure power factor?
    # can measure energy?
    # can measure frequency?
    # is accepted for publication by SPEC?
    # PTD version (see below)
    # Host OS info
    # PTD mode
    # is accuracy estimation enabled?
    # is range setting enabled?
    # number of channels
    my $tmp = $sock->getline();
    $tmp =~ tr/\015\012//d;
    $meterref->{'responses'} = [ $tmp ];
    @{$meterref}{qw(driver interval can_watts can_volts can_amps can_pf
                    can_energy can_freq is_accepted ptd_version host_os
                    ptd_mode can_accuracy can_rangeset channels rest)
                } = split(/,/, $tmp, 16);
    delete $meterref->{'rest'} unless defined($meterref->{'rest'});
    ::Log(134, "  PTD\@$host:$port returns '$tmp' for Identify\n");
    if ($meterref->{'ptd_version'} =~ /^version=([^-]+)-([0-9a-f]{8})(?:-(\d{4})(\d{2})(\d{2}))?(?:;module=([^-]+)-([0-9a-f]{8})\((\d+)\))?$/i) {
      @{$meterref}{qw(ptd_version ptd_crc)} = ($1, $2);
      if (!defined($3)) {
        ::Log(0, "ERROR: Could not get build date for PTD at $host:$port\n");
        $sock->close();
        $sock = -1;
        next;
      }
      $meterref->{ptd_build_date} = "$3-$4-$5";
      if (defined($6)) {
        @{$meterref}{qw(meter_mod_version meter_mod_crc meter_mod_size)} = ($6, $7, $8);
      }
      $meterref->{'ptd_full_version'} = $meterref->{'ptd_version'};
      $meterref->{'ptd_version'} =~ s/\D+$//; # Trim off tags so that
                                              # comparisons will work properly
      if (defined($meterref->{ptd_version}) && $meterref->{ptd_version} lt "1.4.1") {
        ::Log(0, "ERROR: The version of PTD running on $host:$port is too old! v1.4.1 or later is required.\n");
        $sock->close();
        $sock = -1;
        next;
      }
    } else {
      ::Log(0, "ERROR: Could not parse complete version string from PTD ($host:$port) Identify response\n");
      $sock->close();
      $sock = -1;
      next;
    }
    $meterref->{'driver'} =~ s/-na$//;   # Get rid of the "None" IDN string
    $meterref->{'host_os'} =~ s/^OS=//;
    $meterref->{'ptd_mode'} =~ s/^mode=//;
    if ($meterref->{'ptd_mode'} eq 'temperature') {
        # Convert field names for temp. meters
        @{$meterref}{qw(can_temperature can_humidity)} = @{$meterref}{qw(can_watts can_volts)};
        # Remove unused ones
        delete @{$meterref}{qw(can_watts can_volts can_amps can_pf can_energy
                               can_freq)};
    }
    # Turn all the numbers into numbers
    foreach my $tmpkey (keys %{$meterref}) {
        $meterref->{$tmpkey} += 0 if ($meterref->{$tmpkey} =~ /^\d+$/);
    }

    # Reset any measurements that may be on-going
    if ($meterref->{ptd_version} ge '1.4.2') {
      $sock->print("Reset\r\n");
    } else {
      # Just in case
      $sock->print("Stop\r\n");
    }
    $tmp = $sock->getline();

    # Try to figure out the clock skew (if any) between the PTD host and here
    $tmp = meter_time_offset($meterref);
    if (!defined($tmp)) {
        ::Log(0, "ERROR: Failed trying to calculate time offset for PTD host at $host:$port\n");
        $sock->close();
        $sock = -1;
        next;
    }
        
    ::Log(134, "  Clock skew from PTD host at $host:$port is $tmp ms\n");
    $meterref->{'offset'} = ($tmp / 1000) if defined($tmp);

    # Set up ranges (if necessary)
    if (!meter_set_range($meterref, $ranges)) {
        # meter_set_range will log an error if there is one
        $sock->close();
        $sock = -1;
        next;
    }

    push @rc, $meterref;
  }

  if ($sock == -1) {
    # Close open connections (if any)
    foreach my $meterref (@rc) {
      if (defined($meterref->{'sock'}) && $meterref->{'sock'}->connected != undef) {
        # This should always be true
        $meterref->{'sock'}->close();
      }
    }
    ::Log(0, "ERROR: Communications could not be established with one or more power analyzers.\n");
    return undef;
  } else {
    return (1, @rc);
  }
}

# Attempt to figure out the time difference between the clocks on the PTD
# host and this system by starting a measurement and polling for timestamped
# samples.  Do this for 5 samples (2-25 seconds).  Ignore results that are
# < 1 sampling interval, as RL can wait that long to return a sample if one
# isn't immediately available.
sub meter_time_offset {
  my ($meter) = @_;
  my @offsets = ();

  return undef unless defined($meter->{'sock'}) && defined($meter->{'sock'}->connected);
  my $sock = $meter->{'sock'};

  # Start a measurement
  $sock->print("Go,0,0\n");
  my $tmp = get_expected_line($meter, 'Starting untimed measurement', 'attempting to start time calibration run');
  return undef unless defined($tmp);

  # Give it a few sampling intervals to start up, then start reading
  my $waittime = int(3 * ($meter->{'interval'} / 1000));
  $waittime = 3 if ($waittime < 3);
  sleep($waittime);

  # Check for meter connectivity
  $sock->print("R*\n");
  $tmp = get_expected_line($meter, qr/(?:Watts|Temperature),[0-9]/, 'checking basic functionality');
  return undef unless defined($tmp);

  while (@offsets < 5) {
    # There's a little race in PTD's RL command.  If there are no available
    # samples, it will wait one sampling interval for one to show up.
    # Unfortunately, if the wait begins at the same time the previous sample
    # was taken, it'll finish before the next sample shows up.  So, a little
    # delay here will help keep that from happening...
    sleep(0.1);
    $sock->print("RL,1\n");
    $tmp = get_expected_line($meter, 'Last 1 sample', 'attempting to read sample during time calibration run');
    return undef unless defined($tmp);
    my $now = Time::HiRes::time;
    $tmp = get_expected_line($meter, 'Time,', 'attempting to read sample during time calibration run');
    return undef unless defined($tmp);
    if ($tmp =~ /^Time,([^,]+),/) {
      push @offsets, ($now - ptdtime2time($1)) * 1000;
    }
  }

  # Stop the measurement
  $sock->print("Stop\n");
  $tmp = $sock->getline();

  # Average the offsets
  my $avg = 0;
  foreach my $offset (@offsets) {
    $avg += $offset;
  }
  $avg /= @offsets;

  if (abs($avg) < $meter->{'interval'}) {
    # This is within measurement error, so ignore it
    return 0;
  }

  ::Log(33, "Calculated time offset for meter at ".$meter->{'name'}." is ${avg}s\n");
  return $avg;
}

sub get_expected_line {
  my ($meter, $expected, $what) = @_;

  my $tmp = $meter->{'sock'}->getline();
  if ($tmp !~ /^$expected/) {
    ::Log(0, "ERROR: Got '$tmp' (expected '$expected...') when $what on PTD at ".$meter->{'name'}."\n");
    $meter->{'sock'}->print("Stop\n");
    $tmp = $meter->{'sock'}->getline();
    return undef;
  }
  return $tmp;
}

# Add the given time interval into the supplied sequence, extending or merging
# intervals as necessary.  The new time interval is given as the END time and
# the duration.  This assumes that the interval list is ordered by start time
# and does not contain any overlapping intervals.
sub add_interval {
  my ($list, $end, $duration) = @_;

  return unless ref($list) eq 'ARRAY';

  my $start = $end - $duration;
  for(my $i = 0; $i < @{$list}; $i++) {
    my $interval = $list->[$i];
    if ($interval->[0] <= $start && $start <= $interval->[1]) {
      # This is an overlapping interval
      if ($end > $interval->[1]) {
        # It extends the current interval (move the end)
        my ($tmpstart, $tmpend) = ($interval->[0], $end);
        splice @{$list}, $i, 1;
        add_interval($list, $tmpend, $tmpend-$tmpstart);
      }
      return;

    } elsif ($interval->[0] <= $end && $end <= $interval->[1]) {
      # This is also an overlapping interval
      if ($start < $interval->[0]) {
        # It extends the current interval (move the start)
        my ($tmpstart, $tmpend) = ($start, $interval->[1]);
        splice @{$list}, $i, 1;
        add_interval($list, $tmpend, $tmpend-$tmpstart);
      }
      return;

    } elsif ($start < $interval->[0] && $interval->[0] > $end) {
      # Precedes the current interval
      splice @{$list}, $i, 0, [ $start, $end ];
      return;
    } elsif ($start < $interval->[0] && $end > $interval->[1]) {
      # Encloses the current interval
      splice @{$list}, $i, 1, [ $start, $end ];
      return;
    }
  }
  # If we get here, then it's a new interval
  push @{$list}, [ $start, $end ];

  return;
}

# Given a list of meter references ($name, $socket, @responses),
# tell them to start measuring and collect their responses into
# the list.
sub meter_start {
  my ($mark, $ranges, @meterlist) = @_;
  
  return 1 if @meterlist == 0;

  foreach my $meter (@meterlist) {
    if (!meter_set_range($meter, $ranges)) {
      return 0;
    }
  }

  if (defined($mark) && $mark !~ m#^\s*$#) {
    $mark = ','.$mark;
  }

  send_to_meters("Go,0,0$mark\r\n", @meterlist);

  # Now that they're all started, find out what they all said
  get_meter_responses('Go', \@meterlist, qr/^Starting untimed/);

  # XXX What does it look like when this fails?
  return 1;
}

# Given a list of meter references ($name, $socket, @responses),
# tell them to change the logging mark.
sub meter_mark {
  my ($mark, @meterlist) = @_;
  my @rc = ();

  return 1 if (!defined($mark) || $mark =~ m#^\s*$#);
  return 1 if @meterlist == 0;

  send_to_meters("Mark,$mark\r\n", @meterlist);

  # Now that they're all started, find out what they all said
  get_meter_responses('Mark', \@meterlist);

  # XXX What does it look like when this fails?
  return 1;
}

# Given a list of meter references ($name, $socket, @responses),
# tell them to stop measuring power.
sub meter_stop {
  my (@meterlist) = @_;

  send_to_meters("Stop\r\n", @meterlist);

  # Now that they're all stopped, find out what they all said
  get_meter_responses('Stop', \@meterlist, qr/^Stopping/);

  return 1;
}

# Use "RL" to get samples with timestamps
sub do_RL {
    my ($samplehash, $fieldlist, @meterlist) = @_;
    my ($min, $max);
    my $isok = 1;
    my %rc = ();

    if (defined($samplehash)) {
        if (reftype($samplehash) ne 'HASH') {
            ::Log(0, "ERROR: bad value in samplehash parameter for do_RL()\n");
            return (0);
        }
    } else {
        $samplehash = {};
    }
    if (reftype($fieldlist) ne 'HASH' || (keys %{$fieldlist}) == 0) {
        ::Log(0, "ERROR: bad value in fieldlist parameter for do_RL()\n");
        return (0);
    }

    my $fieldre = '^('.join('|', keys %{$fieldlist}).')$';
    $fieldre = qr/$fieldre/;

    foreach my $meter (@meterlist) {
        my $channel = ($meter->{'channels'} > 1) ? ",*" : '';
        # Ask for the uncertainties
        my $cmd = 'Uncertainty';
        if ($meter->{'ptd_version'} le '1.4.2') {
            # In PTD 1.4.2 and earlier, only the Accuracy command supports
            # multi-channel readouts.  The content is the same; only the
            # name of the command and the response tags differ.
            $cmd = 'Accuracy';
        }
        send_to_meters("$cmd$channel\r\n", $meter);
        my $tmp = $meter->{'sock'}->getline();
        $tmp =~ tr/\012\015//d;
        push @{$meter->{'responses'}}, $tmp;
        my @uncertainties = ();
        if ($tmp =~ s/$cmd,//) {
            # Normal response
            my @vals = split(/,/, $tmp);
            while(@vals) {
                my ($acc_avg, $acc_min, $acc_max, $acc_total, $acc_invalid, $acc_valid, $acc_unknown) = splice @vals, 0, 7;
                next unless ($acc_avg >= 0);
                push @{$rc{$meter->{'name'}}->{'uncertainty'}}, [ $acc_avg, $acc_min, $acc_max, $acc_total, $acc_invalid, $acc_valid, $acc_unknown ];
            }
        }

        send_to_meters("RL,*$channel\r\n", $meter);

        # The first line should say how many samples we're getting
        $tmp = $meter->{'sock'}->getline();
        $tmp =~ tr/\012\015//d;
        push @{$meter->{'responses'}}, $tmp;
        my $samples = 0;
        if ($tmp =~ /Last (\d+) sample/) {
            # This is normal
            $samples = $1;
            if (exists($samplehash->{$meter}) && defined($samplehash->{$meter}) && $samples != $samplehash->{$meter}) {
                $isok = 0;
                ::Log(0, "Meter '".$meter->{'name'}."' reported ".$samplehash->{$meter}." samples, but returned $samples sample values\n");
            }
        } elsif ($tmp =~ /^Invalid/) {
            # Something's wrong
            ::Log(0, "Meter '".$meter->{'name'}."' returned '$tmp' in response to 'RL,*$channel' command.\n");
            $isok = 0;
            next;
        }
        if ($samples == 0 || $tmp =~ /(?:Insufficient|No) unread/) {
            # No samples?
            ::Log(0, "Meter '".$meter->{'name'}."' reports no samples available in response to 'RL,*$channel' command.\n");
            $isok = 0;
            next;
        }

        # Read all the samples
        while($samples > 0) {
            $samples--;
            $tmp = $meter->{'sock'}->getline();
            $tmp =~ tr/\012\015//d;
            push @{$meter->{'responses'}}, $tmp;
            my @fields = split(/,/, $tmp);
            if ($fields[0] ne 'Time') {
                ::Log(0, "Meter '".$meter->{'name'}."' returned unexpected line '$tmp' when reading samples from RL command.\n");
                $isok = 0;
                next;
            }
            shift (@fields);      # Eat the 'Time'
            my $field = shift(@fields);
            my $ts = ptdtime2time($field, $meter->{'offset'});
            if (!defined($ts)) {
                ::Log(0, "Error: Could not read timestamp from '$field'\n");
                $isok = 0;
                next;
            }
            my %counts = ();
            my %vals = ();
            while (@fields) {
                my ($field, $val) = (shift(@fields), shift(@fields));
                if ($field !~ /^[A-Z]/) {
                    ::Log(0, "Error parsing field data from RL command; got field '$field' with value '$val'\n");
                    $isok = 0;
                    last;
                }

                # Don't store fields that the meter says it can't provide
                next unless $meter->{'can_'.lc($field)};

                $counts{$field} = 0 unless defined($counts{$field});
                $min = $val if ($field =~ /$fieldre/ && ($min > $val || $counts{$field} == 0 || !defined($min)));
                $max = $val if ($field =~ /$fieldre/ && ($max < $val || $counts{$field} == 0 || !defined($max)));
                $vals{$field}->[$counts{$field}] = $val + 0;
                $counts{$field}++;
            }

            # Save off the fields of interest, as well as the timestamp
            my %tmprec = ( 'ts' => $ts );
            my $gotsome = 0;
            foreach my $field (grep { reftype($vals{$_}) eq 'ARRAY' } keys %{$fieldlist}) {
                if ($meter->{'channels'} > 1 && @{$vals{$field}} == ($meter->{'channels'} + 1)) {
                    # Get rid of the first element; it's the "sum" channel.  We'll
                    # do our own summing.
                    shift @{$vals{$field}};
                }
                $tmprec{$fieldlist->{$field}} = [ @{$vals{$field}} ];
                $gotsome++;
            }
            push @{$rc{$meter->{'name'}}->{'samples'}}, { %tmprec } if $gotsome;
        }
    }

    return ($isok, %rc);
}

sub trim_and_average {
    my ($sampleref, $discard) = @_;
    my ($label, $old_avg, $old_min, $old_max, $old_samples) = ($sampleref->[0], @{$sampleref->[1]->{'pwrstat'}}[0..3]);
    $label = "meter '".$label."'";

    if ($discard == 0) {
        # Easy
        return ($old_avg, $old_min, $old_max, $old_samples, @{$sampleref}[2..$#{$sampleref}]);
    }

    # Filter out "error" values
    my @samples = ();
    foreach my $sample (@{$sampleref}[2..$#{$sampleref}]) {
        if (grep { $_ < 0 } @{$sample->{'pwr'}}) {
            # Bad value on at least one channel; skip it
            next;
        }
        push @samples, $sample;
    }

    my ($avg, $min, $max);

    if (@samples < ($discard * 2) * 2) {
        # Let's not discard more than half the samples
        Log(1, ucfirst($label)." does not have enough samples to support clipping " .
               "and re-averaging! (needs ".($discard * 2 * 2).", has ".(@samples+0).")\n");
        return undef;
    } else {
        my $old_samples = @samples+0;
        Log(27, "Clipping ".($discard * 2)." samples from $label\n");
        # Trim from the beginning
        splice(@samples, 0, $discard);
        # Trim from the end
        splice(@samples, -$discard, $discard);
        # Get the local min and max and average
        my @sample_sums = sort { $a <=> $b } map { sum_channels($_) } @samples;
        ($min, $max) = @sample_sums[0, -1];
        my $numsamples = @samples+0;
        my $total = 0;
        foreach my $sample (@sample_sums) {
            $total += $sample;
        }
        $avg = $total / $numsamples;
        Log(127, sprintf("%s differences: avg: %+g (%+g%%); min: %+g (%+g%%); max: %+g (%+g%%); samples: %d (%+g%%)\n",
                         ucfirst($label),
                         ($avg - $old_avg),
                         $old_avg ? (($avg - $old_avg) / $old_avg) * 100 : 'INF',
                         ($min - $old_min),
                         $old_min ? (($min - $old_min) / $old_min) * 100 : 'INF',
                         ($max - $old_max),
                         $old_max ? (($max - $old_max) / $old_max) * 100 : 'INF',
                         ($numsamples - $old_samples),
                         $old_samples ? (($numsamples - $old_samples) / $old_samples) * 100 : 'INF'));
    }

    return($avg, $min, $max, (@samples+0), @samples);
}

# Given a list of power analyzer references, ask them for the average power
# measured and return the total average power, average average power, maximum
# uncertainty, and average uncertainty, as well as the full list of returned
# per-meter values.
sub power_analyzer_watts {
  my ($error_percentage, @meterlist) = @_;
  my @rc = ();
  my ($isok, $total, $meters, $min, $max) = (1, 0, 0, 2_999_999_999, 0);
  my %tmprc = ();
  my $error_reltol = $error_percentage / 100;

  return ($isok) if @meterlist == 0;

  # "RR" to get ranging settings
  foreach my $meter (@meterlist) {
      my $channel = ($meter->{'channels'} > 1) ? ',*' : '';
      send_to_meters("RR$channel\r\n", $meter);
      my ($ampauto, $amprange, $voltauto, $voltrange);
      my $tmp = $meter->{'sock'}->getline();
      $tmp =~ tr/\015\012//d;
      ::Log(134, "Meter '".$meter->{'name'}."' returned '$tmp' to 'RR$channel' command\n");
      push @{$meter->{'responses'}}, $tmp;
      my @vals = split(/,/, $tmp);
      shift(@vals);     # Get rid of the command tag
      my @chanvals = ();
      while(@vals) {
          push @chanvals, [ splice @vals, 0, 4 ];
      }
      if (@chanvals == $meter->{'channels'}+1) {
          # PTD 1.4.3+ includes the "virtual sum" channel as the first set of
          # values, so get rid of it
          shift @chanvals;
      } elsif (@chanvals < $meter->{'channels'}) {
          ::Log(0, "ERROR: Response to read range command from PTD at ".$meter->{'name'}." did not return data for all channels!\n");
          return 0;
      }
      while (@chanvals) {
          my $chandata = shift(@chanvals);
          my ($ampauto, $amprange, $voltauto, $voltrange) = @{$chandata};
          if (($amprange < 0 && $ampauto <= 0) || ($voltrange < 0 && $voltauto <= 0)) {
              # Nonsense ranges; the meter probably doesn't support reporting them
              push @{$tmprc{$meter->{'name'}}->{'range'}}, [ undef, undef ];
          } else {
              # Record amp and volt ranges; -1 means auto-ranging is on
              $amprange = -1 if $ampauto;
              $voltrange = -1 if $voltauto;
              push @{$tmprc{$meter->{'name'}}->{'range'}}, [ $amprange, $voltrange ];
          }
      }
  }

  # "Watts" to get aggregated data
  send_to_meters("Watts\r\n", @meterlist);
  foreach my $meter (@meterlist) {
      my ($avg, $tmp_min, $tmp_max, $samples, $errors, $valid_samples);
      my $tmp = $meter->{'sock'}->getline();
      $tmp =~ tr/\015\012//d;
      my ($cmd, @vals) = split(/,/, $tmp);
      ::Log(134, "Meter '".$meter->{'name'}."' returned '$tmp' to 'Watts' command\n");
      push @{$meter->{'responses'}}, $tmp;
      ($avg, $tmp_min, $tmp_max, $samples, $errors, $valid_samples) = @vals;
      # Convert everything to numbers
      $avg += 0;
      $tmp_min += 0;
      $tmp_max += 0;
      $samples += 0;
      $errors += 0;
      $valid_samples += 0;
      $total += $avg;
      if ($errors != 0) {
          ::Log(0, "Meter '".$meter->{'name'}."' reports $errors errors\n");
          $isok = 0 if ($errors > ($samples * $error_reltol));
      }
      if ($samples != $valid_samples) {
          ::Log(0, "Meter '".$meter->{'name'}."' reports $samples samples, of which only $valid_samples are good\n");
          $isok = 0 if (($samples - $valid_samples) > ($samples * $error_reltol));
      }
      $tmprc{$meter->{'name'}}->{'pwrstat'} = [ $avg, $tmp_min, $tmp_max, $samples, $errors, $valid_samples ];
      $meters++;
  }

  my ($tmpok, %watts_list) = do_RL({ map { $_->{'name'} => $tmprc{$_->{'name'}}->{'pwrstat'}->[3] } (grep { ::check_elem('ARRAY', $tmprc{$_->{'name'}}, 'pwrstat') } @meterlist) },
                                   { 'Watts' => 'pwr' },
                                   @meterlist);
  $isok &= $tmpok;

  # Assemble the saved values to return
  my ($uncertainty_total, $max_uncertainty) = (0, undef);
  foreach my $meter (@meterlist) {
      my $uncertainty = $watts_list{$meter->{'name'}}->{'uncertainty'};
      if (reftype($uncertainty) ne 'ARRAY') {
          ::Log(0, "ERROR: Power analyzer '".$meter->{'name'}."' returned no measurement uncertainty information\n");
          $isok = 0;

          # Fake it up so its power data is still returned
          $uncertainty = $watts_list{$meter->{'name'}}->{'uncertainty'} = [];
      }
      foreach my $channelref (@{$uncertainty}) {
          my ($acc_avg, $acc_min, $acc_max, $acc_total, $acc_invalid, $acc_valid, $acc_unknown) = (0, 0, 0, 0, 0, 0, 0);
          ($acc_avg, $acc_min, $acc_max, $acc_total, $acc_invalid, $acc_valid, $acc_unknown) = @{$channelref} if reftype($channelref) eq 'ARRAY';
          $max_uncertainty = $acc_max if !defined($max_uncertainty) || ($acc_max > $max_uncertainty);
          $uncertainty_total += ($acc_avg * $tmprc{$meter->{'name'}}->{'pwrstat'}->[0]);
          if ($acc_total > 0) {
              # Check to see that uncertainty requirements are met
              # No more than 1% samples may have unknown uncertainty
              if ($acc_total * ($::global_config->{'max_unknown_uncertainty'} / 100) < $acc_unknown) {
                  ::Log(0, "ERROR: Number of samples with unknown uncertainty from $meter->{'name'} exceeds ".$::global_config->{'max_unknown_uncertainty'}."%\n");
                  $isok = 0;
              }
              if ($acc_avg > ($::global_config->{'max_average_uncertainty'} / 100)) {
                  ::Log(0, "ERROR: Average uncertainty of all samples from $meter->{'name'} exceeds ".$::global_config->{'max_average_uncertainty'}."%\n");
                  $isok = 0;
              }
              if ($acc_invalid / $acc_total > $::global_config->{'uncertainty_exception'}) {
                  ::Log(0, sprintf("ERROR: Too many samples (%.2f%%) from %s have an uncertainty of more than %d%%\n", ($acc_invalid / $acc_total), $meter->{'name'}, $::global_config->{'max_average_uncertainty'}));
                  $isok = 0;
              }
          }
      }
      push @rc, [ $meter->{'name'},
                  {
                    %{$tmprc{$meter->{'name'}}},
                    'accstat' => $watts_list{$meter->{'name'}}->{'uncertainty'}
                  },
                  @{$watts_list{$meter->{'name'}}->{'samples'}}
                ];
  }

  my $avg = undef;
  if ($meters > 0) {
      $avg = $total/$meters;
      ::Log(33, "Watts reading returns preliminary watts(total=$total, avg=$avg) uncertainty(max=$max_uncertainty, avg=".($uncertainty_total/$total).")\n");
  } else {
      ::Log(33, "Watts reading returns preliminary watts(total=$total, avg=UNDEF(no meters)) uncertainty(max=$max_uncertainty, avg=".($uncertainty_total/$total).")\n");
  }
  return ($isok, $total, $avg, $max_uncertainty, $uncertainty_total/$total, @rc);
}

# Trim a list of samples based on time.  Return total, average, min, max, and
# the list of new samples.
sub extract_samples {
  my ($meterlist, $intervals, $discard) = @_;
  my ($total, $avg, $min, $max) = (0);
  my @sample_totals = ();
  my @return_samples = ();

  foreach my $meter (@{$meterlist}) {
    # Save the info + aggregate data
    my $name = $meter->[0];
    my ($mavg, $mmin, $mmax, $num_samples, $errors, $valid) = @{$meter->[1]->{'pwrstat'}};
    my @keep = ();
    for(my $i = 2; $i < @{$meter}; $i++) {
      foreach my $interval_ref (@{$intervals}) {
        my ($start, $end) = @{$interval_ref};
        if ($meter->[$i]->{'ts'} < $start) {
          # Won't be in this list of intervals
          last;

        } elsif ($meter->[$i]->{'ts'} <= $end) {
          # It's a keeper
          push @keep, $meter->[$i];
          last;

        } elsif (@keep == 0 && int($meter->[$i]->{'ts'}) <= $end) {
          # Relax the restrictions a little bit so that at least ONE
          # sample will be taken.  This should only happen when the
          # benchmark run takes less time than the meter sampling
          # interval.
          push @keep, $meter->[$i];
          last;
        }
      }
    }

    return undef unless @keep;

    # Recalculate the meter-local metrics
    ($mmin, $mavg, $mmax, $num_samples, $valid) = (undef, 0, undef, 0, 0);

    for(my $i = 0; $i < @keep; $i++) {
      my $sum = sum_channels($keep[$i]);
      $mavg += $sum;
      $mmin = $sum if (!defined($mmin) || $sum < $mmin);
      $mmax = $sum if (!defined($mmax) || $sum > $mmax);
      $num_samples++;
      # Just assume that selected samples are okay...
      $valid++;

      # Add each sample to the totals; this assumes that all meters
      # run at the same sample rate and start and end at the same
      # time.  This array is used to figure global min and max.
      $sample_totals[$i] += $sum;
    }
    $mavg /= @keep;
    $total += $mavg;
    
    # Throw it back on the pile...
    push @return_samples, [
                            $name,
                            { 'pwrstat' => [ $mavg, $mmin, $mmax,
                                             $num_samples, $errors, $valid ],
                              'accstat' => [ @{$meter->[1]->{'accstat'}}   ],
                              'range'   => [ @{$meter->[1]->{'range'}}     ]
                            },
                            @keep
                          ];
  }

  # Trim the sample list and re-average
  if ($discard > 0) {
      $total = 0;
      @sample_totals = ();
      foreach my $meter (@return_samples) {
          my ($new_avg, $new_min, $new_max, $numsamples, @samples) =
              trim_and_average($meter, $discard);
          if (defined($new_avg)) {
              # Uncomment this to trim the list of stored samples to match
              # the list used to generate the new min/average/max.
              #splice @{$meter}, 2, @{$meter}-2, @samples;

              # Add each sample to the totals; this assumes that all meters
              # run at the same sample rate and start and end at the same
              # time.  This array is used to figure global min and max.
              for(my $i = 0; $i < @samples; $i++) {
                  $sample_totals[$i] += sum_channels($samples[$i]);
              }
              $total += $new_avg;

              # Get previous values for sample counts, etc.
              my ($samples, $errors, $valid_samples) = @{$meter->[1]->{'pwrstat'}}[4..6];

              # Because it's unlikely that the trimming will get rid of
              # any of the bad samples, keep the error counts and the
              # valid sample count relatively the same as it was before.
              # This COULD push the number of bad samples over the
              # meter_errors_percentage threshold, but ignore it.
              # So...
              $valid_samples = @{$meter} - ($samples - $valid_samples) - 2;
              $samples = @{$meter}-2;

              $meter->[1]->{'pwrstat'} = [ $new_avg, $new_min, $new_max, $samples, $errors, $valid_samples ];
          } 
      }
  }
  # Figure out global min/max
  @sample_totals = sort { $a <=> $b } @sample_totals;
  ($min, $max) = @sample_totals[0, @sample_totals-1];

  return ($total, $total/@{$meterlist}, $min, $max, @return_samples);
}

sub sum_channels {
  my ($sample) = @_;
  my $sum = 0;

  return undef unless (ref($sample) eq 'HASH');

  foreach my $reading (@{$sample->{'pwr'}}) {
    $sum += $reading;
  }

  return $sum;
}

# Convert a PTD RL timestamp to localtime, possibly with compensation
sub ptdtime2time {
  my ($ts, $offset) = @_;

  my $ptdtime = undef;
  if ($ts =~ /^(\d+)-(\d+)-(\d+) (\d+:\d+:\d+\.\d+)$/) {
    $ptdtime = str2time("$3-$1-$2T$4");
    $ptdtime += $offset if defined($offset);
  }

  return $ptdtime;
}

# Given a PTD command that will return the standard (avg, min, max), return
# the average average, lowest, and highest, along with the full list of
# returned per-meter values.
sub temp_meter_temp_and_humidity {
  my ($error_percentage, @meterlist) = @_;
  my $isok = 1;
  my $error_reltol = $error_percentage / 100;
  my @rc = ();
  my $rc = {
            'temperature' => [
                               undef, # average
                               undef, # min
                               undef, # max
                               []     # meter+samples list
                             ],
            'humidity' => [
                            undef, # average
                            undef, # min
                            undef, # max
                            []     # meter+samples list
                          ]
           };

  return $isok if @meterlist == 0;

  # Collect the avg/min/max data
  foreach my $cmd (qw(Temperature Humidity)) {
      my ($total, $meters, $min, $max, @samples) = (0, 0, undef, undef, undef);
      my %tmprc = ();
      send_to_meters("$cmd\r\n", @meterlist);

      # Collect the responses
      foreach my $meter (@meterlist) {
          my $tmp = $meter->{'sock'}->getline();
          $tmp =~ tr/\015\012//d;
          ::Log(134, "Meter '".$meter->{'name'}."' returned '$tmp' to '$cmd' command\n");
          push @{$meter->{'responses'}}, $tmp;
          my ($cmd, $avg, $tmp_min, $tmp_max, $samples, $errors, $valid_samples) = split(/,/, $tmp);
          if ($avg < 0 && $samples == 0) {
            # PTD has indicated that the measurement is unsupported, or that
            # there's an error
            if ($cmd eq 'Temperature') {
                # Problem; all temp sensors should measure temperature
                ::Log(0, "Temperature meter '".$meter->{'name'}."' indicates an error or lack of samples\n");
                $isok = 0;
            }
            # No problem for humidity; some temp sensors don't measure that
            next;
          }
          # Convert everything to numbers
          $avg += 0;
          $tmp_min += 0;
          $tmp_max += 0;
          $samples += 0;
          $errors += 0;
          $valid_samples += 0;
          if ($errors != 0) {
              ::Log(0, "Meter '".$meter->{'name'}."' reports $errors errors\n");
              $isok = 0 if ($errors > ($samples * $error_reltol));
          }
          if ($samples != $valid_samples) {
              ::Log(0, "Meter '".$meter->{'name'}."' reports $samples ".lc($cmd)." samples, of which only $valid_samples are good\n");
              $isok = 0 if (($samples - $valid_samples) > ($samples * $error_reltol));
          }
          $tmprc{$meter->{'name'}} = [ $meter->{'name'}, $avg, $tmp_min, $tmp_max, $samples, $errors, $valid_samples ];
          $min = $tmp_min if ($tmp_min < $min || !defined($min));
          $max = $tmp_max if ($tmp_max < $max || !defined($max));
          $total += $avg;
          $meters++;
      }
      if ($meters > 0) {
          ::Log(33, lc($cmd)." readings return avg=".($total/$meters).", min=$min, max=$max\n");
          $rc->{lc($cmd)} = [ $total/$meters, $min, $max, (values %tmprc) ];
      }
  }

  # Use "RL" to get samples with timestamps
  my ($tmpok, %tempout) = do_RL({ map { $_->[0] => $_->[4] } @{$rc->{'temperature'}}[3..$#{$rc->{'temperature'}}] },
                                { 'Temperature' => 'temp',
                                  'Humidity'    => 'hum' },
                                @meterlist);
  $isok &= $tmpok;

  # Assemble the saved values to return
  @rc = ( $rc );
  foreach my $meter (sort { $a->{'name'} cmp $b->{'name'} } @meterlist) {
      push @rc, [ $meter->{'name'}, @{$tempout{$meter->{'name'}}->{'samples'}} ] if reftype($tempout{$meter->{'name'}}->{'samples'}) eq 'ARRAY';
  }

  return ($isok, @rc);
}

# Find out if specinvoke understands the given option.
sub specinvoke_can {
  my ($opt) = @_;
  my $rc = 0;

  my $specrun = jp($::global_config->top, 'bin', $::global_config->specrun);
  my $tmp = qx/$specrun $opt -h 2>&1/;
  $? = 0;       # So as to not taint other things
  if ($tmp =~ /illegal option --/) {
    return 0;
  } else {
    return 1;
  }
}

# Unitish tests here
if (grep { $_ eq 'test:add_interval' } @ARGV) {
  my @tests = (
  # Start                       New             Expected        Label
  [ [],                         [2,1],          [[1,2]],        'First' ],
  [ [[1,5]],                    [7,1],          [[1,5],[6,7]],  'Append' ],
  [ [[3,4]],                    [2,1],          [[1,2],[3,4]],  'Prepend' ],
  [ [[1,2],[6,7]],              [5,2],          [[1,2],[3,5],[6,7]],'Insert' ],
  [ [[1,2],[3,4]],              [3,1],          [[1,4]],        'Overlap + merge' ],
  [ [[1,4]],                    [6,3],          [[1,6]],        'Extend end' ],
  [ [[4,7]],                    [6,3],          [[3,7]],        'Extend start' ],
  [ [[2,6]],                    [4,2],          [[2,6]],        'Subset start' ],
  [ [[2,6]],                    [6,2],          [[2,6]],        'Subset end' ],
  [ [[2,6]],                    [6,4],          [[2,6]],        'Complete subset' ],
  [ [[3,5]],                    [6,5],          [[1,6]],        'Complete superset' ],
  );
  require Test::More; Test::More->import(tests => @tests+0);
  foreach my $testref (@tests) {
    my ($start, $new, $expected, $label) = @{$testref};
    my @working = @{$start};
    add_interval(\@working, @{$new});
    $Data::Dumper::Indent=0;
    if (!is_deeply(\@working, $expected, $label)) {
      diag(Data::Dumper->Dump([$start, $new, $expected, \@working],[qw(start new expected got)]));
    }
  }
}
  
1;
