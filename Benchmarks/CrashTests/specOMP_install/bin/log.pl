#
# log.pm
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: log.pl 1164 2011-08-19 19:20:01Z CloyceS $

use strict;
use IO::File;

my $version = '$LastChangedRevision: 1164 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'log.pl'} = $version;

$::log_handle = new IO::File ">&STDOUT";
$::all_log_handle = undef;

# Construct an intro to the debug log
my $debug_intro = <<EOF
==============================================================================
Debug log for ${main::suite}.  This file contains very detailed debugging
output from the ${main::suite} tools (as if "--verbose 99" had been specified) and is
typically useful only to developers of the ${main::suite} toolset.   

For a successful run, this debug log will be removed automatically, unless you
specify "--keeptmp" on the command line, or "keeptmp=1" in your config file.

If you file a support request with ${main::lcsuite}support\@spec.org, you may be
asked to submit this file.
------------------------------------------------------------------------------

Environment variables that should have been set or changed by shrc:
EOF
;

# Add in the current setting of the PATH and SPEC* environment variables
$debug_intro .= "SPEC: $ENV{'SPEC'}\n";
$debug_intro .= "PATH: $ENV{'PATH'}\n";
$debug_intro .= "SPECPERLLIB: $ENV{'SPECPERLLIB'}\n";
$debug_intro .= "LD_LIBRARY_PATH: $ENV{'LD_LIBRARY_PATH'}\n";
$debug_intro .= "DYLD_LIBRARY_PATH: $ENV{'DYLD_LIBRARY_PATH'}\n";
$debug_intro .= "LC_ALL: $ENV{'LC_ALL'}\n";
$debug_intro .= "LC_LANG: $ENV{'LC_LANG'}\n";

# And others that may be of interest
foreach my $var (grep { /^(?:SPEC|SHRC)/ } sort keys %ENV) {
    next if $var =~ /^(?:SPEC|SPECPERLLIB)$/;
    $debug_intro .= "$var: $ENV{$var}\n";
}

$debug_intro .= <<EOF2
------------------------------------------------------------------------------

Runspec's verbose version output:
EOF2
;
$debug_intro .= ::verbose_version_string();

$debug_intro .= "\n==============================================================================\n\n";

require 'log_common.pl';

sub open_log {
    my ($config, $subnum, $filename, $skip_intro) = @_;
    my $top = $config->top;
    if ($config->output_root ne '') {
      $top = $config->output_root;
    }
    my $subdir = $config->expid;
    $subdir = undef if $subdir eq '';

    my $locked = 0;
    my $origumask = umask;
    my ($rc, $what, $stuff) = (0, undef, undef);
    my $fh = new IO::File;
    $::all_log_handle = new IO::File;

    # Find a name
    my $dir  = jp($top, $config->resultdir, $subdir);
    eval { mkpath($dir) };
    if ($@) {
        Log(0, "ERROR: Couldn't create directory for log files: $@\n");
        return wantarray ? (0, undef) : 0;
    }
    my $name = jp($dir, ($filename ne '') ? $filename : $config->prefix . $config->log);
    my $lockfile = jp(dirname($name), 'lock.'.basename($name));

    if ((!defined($subnum) || $subnum eq '') &&
        (!defined($filename) || $filename eq '')) {
	# We've got to be careful about races here, too!
	# Some systems lack the ability to lock files that aren't opened for
	# writing.  So we open a file for writing in $SPEC/result, and make sure
	# that everyone can write to it.
	umask 0000;			# Make sure that everyone can write it
	my $num = undef;
	$rc = $fh->open($lockfile, O_RDWR|O_CREAT, 00666);
	umask $origumask;		# Now put it back
	if (!$rc) {
	    Log(0, "Couldn't open $lockfile for update:\n  $!\nThis makes selecting a run number impossible, so I'm going to bail now.\n");
	    return wantarray ? (0, undef) : 0;
	} elsif (!istrue($config->absolutely_no_locking)) {
	    ($rc, $what, $stuff) = lock_file($fh, $lockfile);
	    if (!defined($rc) || $what ne 'ok') {
		if ($what eq 'unimplemented') {
		    Log(0, "\n\nLOCK ERROR: Your system doesn't seem to implement file locking.  Perl said\n");
		    Log(0, "-------\n$stuff\n-------\n");
		    Log(0, "Because of this, it is not possible to guarantee that the run number (which\n");
		    Log(0, "determines the names of the log and results files) will be unique.  This is\n"); 
		    Log(0, "only an issue if there are concurrent runs happening using this copy of the\n");
		    Log(0, "benchmark tree.\n\n");
		    $locked = 0;
		} elsif ($what eq 'error') {
		    Log(0, "\n\nLOCK ERROR: Could not lock log lock file \"$lockfile\".\n");
		    Log(0, "Perl said\n-------\n$stuff\n-------\n");
		    Log(0, "  It is not safe to attempt to generate a run number, so I'll bail now.\n\n");
		    return wantarray ? (0, undef) : 0;
		}
	    } else {
		$locked = 1;
	    }
	} else {
	    Log(0, "\n\nLOCK WARNING: Run number selection is unprotected; concurrent runs using this\n");
	    Log(0, "              installation may not produce results.\n\n");
	    $locked = 0;
	}
	$fh->seek(0, 0);	# Make sure to only read the first line
	chomp($num = <$fh>);
	$num += 0;  # Make it into a real number
	$name = $lockfile;  # This is just to make the following test succeed
	while (-e $name) {
	    if (!defined($num) || $num <= 0) {
	      $num  = find_biggest_ext($dir, '.log') + 1;
	    } else {
	      $num++;
	    }
	    $num = sprintf("%03d", $num);
	    $fh->seek(0, 0);	# Make sure to only write the first line
	    $fh->printflush("$num\n");
	    $name = jp($dir, $config->prefix . $config->log . ".${num}.log" );
	}
	$config->{'lognum'} = $num;
	if (!defined($::log_handle)) {	# Default open of STDOUT must've failed
	    $::log_handle = new IO::File;
	}
    } elsif (!defined($filename) || $filename eq '') {
	$name = $config->prefix . $config->log . '.' . $config->{'lognum'} . '.log.' . $subnum;
        my $tmpdirname = ::get_tmp_logdir($config, 1);
        if (-d $tmpdirname) {
            # The temporary log directory exists; use it
            $name = jp($tmpdirname, $name);
        } else {
            $name = jp($dir, $name);
        }
    } else {
        # Filename was set, so don't do screen output
        $::log_to_screen = 0;
    }
    if (!$::log_handle->open(">$name")) {
	Log(0, "Couldn't open log file '$name' for writing: $!\n");
    } else {
      $config->{'logname'} = $name if $subnum eq '';
      $::log_opened = 1;
      # Unbuffer the log file
      $::log_handle->autoflush;

      # Output saved logs, if any
      if (@::saved_logs) {
        $::log_handle->print(join('', @::saved_logs)."\n");
        @::saved_logs = ();
      }

      if (!$::all_log_handle->open(">${name}.debug")) {
          Log(0, "Couldn't open log file '${name}.debug' for writing: $!\n");
      } else {
          $::all_log_handle->autoflush;
          $::all_log_handle->print($debug_intro) unless ($::from_runspec || $skip_intro);
          # Output saved logs, if any
          if (@::all_log) {
            $::all_log_handle->print(join('', @::all_log)."\n");
            @::all_log = ();
          }
      }
    }

    if ($locked) {
      # Unlock the file so that others may proceed.
      ($rc, $what, $stuff) = unlock_file($fh);
      if (!defined($rc) || $what ne 'ok') {
        if ($what eq 'unimplemented') {
          # If locking is really unimplemented, $locked shouldn't be set.
          Log(0, "\n\nUNLOCK ERROR: Tried to unlock a file on a system that claims to not support\n");
          Log(0, "        locking.  Please report this error to ${main::lcsuite}support\@spec.org\n"); 
          Log(0, "        at SPEC.  Please include the output from 'runspec -V' in your report.\n");
          Log(0, "About this error, Perl said\n");
          Log(0, "-------\n$stuff\n-------\n\n");
        } elsif ($what eq 'error') {
          Log(0, "\n\nUNLOCK ERROR: Could not unlock log lock file \"$lockfile\".\n");
          Log(0, "The error might have been\n");
          Log(0, "-------\n$stuff\n-------\n");
          Log(0, "Because of this, other runs may wait indefinitely.\n\n");
        }
      }
    }
    $fh->close();		# It'd close when we leave this sub anyway

    return wantarray ? (1, $name) : 1;
}

sub close_log {
  # Flush pending output (if any) here
  my $line = handle_partial('log');
  if ($::log_opened && defined($line) && $line ne '') {
    $::log_handle->print($line."\n");
    $::partial_lines{'log'} = [ undef, 0, 0 ];
  }
  $line = handle_partial('all');
  if ($::log_opened && defined($line) && $line ne '') {
    $::all_log_handle->print($line."\n");
    $::partial_lines{'all'} = [ undef, 0, 0 ];
  }
  $line = handle_partial('screen');
  if (defined($line) && $line ne '') {
    print $line."\n";
    $::partial_lines{'screen'} = [ undef, 0, 0 ];
  }

  if ($::log_opened) {
      if (defined($::log_handle)) {
          $::log_handle->close();
      }
      if (defined($::all_log_handle)) {
          $::all_log_handle->close();
      }
  }
}

sub handle_partial {
    my ($what) = @_;
    my $line = $::partial_lines{$what}->[0];
    if ($::partial_lines{$what}->[1]) {
        my $time = $::partial_lines{$what}->[1];
        if ($::partial_lines{$what}->[2]) {
            $time .= sprintf '(%.3fs)', $::partial_lines{'log'}->[2];
        }
        $line = $time.': '.$line;
    }
    return $line;
}

sub log_header {
    my ($config) = @_;
    my $tune       = join (',', @{$config->tunelist});
    my $action     = $config->action;
    my $verbose    = $config->verbose;
    my $ext        = join (',', @{$config->extlist});
    my $size       = join (',', @{$config->sizelist});
    my $mach       = join (',', @{$config->machlist});
    my $benchmarks = join (',', map {$_->benchmark} @{$config->runlist});
    my $outputs    = join (',', @{$config->formatlist});
    my $username   = $config->username;
    my $env        = "";
    
    # print the preENV settings to the log.
    my @pre_env = grep { /^preENV_/ } sort keys %{$config};
    if (@pre_env) {
      $env = "\n\nEnvironment settings:\n";
      foreach my $var (@pre_env) {
         my $name = $var;
         $name =~ s/^preENV_//;
         $env .= "$name = \"$ENV{$name}\"\n";
      }
    }


    Log(140, <<EOV);
Verbosity = $verbose
Action    = $action
Tune      = $tune
Ext       = $ext
Size      = $size
Machine   = $mach
benchmarks= $benchmarks
outputs   = $outputs
username  = ${username}$env
EOV
}

1;
