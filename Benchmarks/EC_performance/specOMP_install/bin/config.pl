#
# config.pl
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: config.pl 1863 2012-10-01 06:11:11Z CloyceS $
#
package Spec::Config;

use strict;
use IO::File;
use Safe;
use ConfigDumper;
use File::Basename;
use Scalar::Util qw(reftype);
use vars qw(%refmapping);
%refmapping = ();

my $version = '$LastChangedRevision: 1863 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'config.pl'} = $version;

require 'config_common.pl';

# List of variables and settings that are only effective when set in the
# header section.
%::header_only = (
                  'action'                   => 1,
                  'allow_extension_override' => 1,
                  'backup_config'            => 1,
                  'bench_post_setup'         => 1,
                  'build_in_build_dir'       => 1,
                  'check_md5'                => 1,
                  'check_version'            => 1,
                  'command_add_redirect'     => 1,
                  'expand_notes'             => 1,
                  'expid'                    => 1,
                  'ext'                      => 1,
                  'flagsurl'                 => 1,
                  'http_proxy'               => 1,
                  'http_timeout'             => 1,
                  'idledelay'                => 1,
                  'idleduration'             => 1,
                  'idle_current_range'       => 1,
                  'idle_voltage_range'       => 1,
                  'ignore_errors'            => 1,
                  'ignore_sigint'            => 1,
                  'info_wrap_columns'        => 1,
                  'keeptmp'                  => 1,
                  'line_width'               => 1,
                  'locking'                  => 1,
                  'absolutely_no_locking'    => 1,
                  'log_line_width'           => 1,
                  'log_timestamp'            => 1,
                  'mach'                     => 1,
                  'mail_reports'             => 1,
                  'mailcompress'             => 1,
                  'mailmethod'               => 1,
                  'mailport'                 => 1,
                  'mailserver'               => 1,
                  'mailto'                   => 1,
                  'mail_reports'             => 1,
                  'mean_anyway'              => 1,
                  'minimize_builddirs'       => 1,
                  'minimize_rundirs'         => 1,
                  'nobuild'                  => 1,
                  'notes_wrap_columns'       => 1,
                  'notes_wrap_indent'        => 1,
                  'output_format'            => 1,
                  'output_root'              => 1,
                  'post_setup'               => 1,
                  'power'                    => 1,
                  'power_analyzer'           => 1,
                  'preenv'                   => 1,
                  'rate'                     => 1,
                  'rebuild'                  => 1,
                  'reportable'               => 1,
                  'runlist'                  => 1,
                  'section_specifier_fatal'  => 1,
                  'sendmail'                 => 1,
                  'setprocgroup'             => 1,
                  'size'                     => 1,
                  'sysinfo_program'          => 1,
                  'table'                    => 1,
                  'teeout'                   => 1,
                  'temp_meter'               => 1,
                  'tune'                     => 1,
                  'unbuffer'                 => 1,
                  'verbose'                  => 1,
                  'version_url'              => 1,
                  'temp_meter'               => 1,
                  'voltage_range'            => 1,
                 );

%::reserved_words = (
                      'config_inc'	=> 1,
                      'benchmarks'	=> 1,
                      'benchsets'	=> 1,
                      'compile_error'	=> 1,
                      'config'		=> 1,
                      'files_read'	=> 1,
                      'flaginfo'	=> 1,
                      'oldmd5'		=> 1,
                      'orig_argv'	=> 1,
                      'orig_env'	=> 1,
                      'pptxtconfig'	=> 1,
                      'rawformat_opts'	=> 1,
                      'rawtxtconfig'	=> 1,
                      'rawtxtconfigall'	=> 1,
                      'refs'		=> 1,
                      'seen_extensions'	=> 1,
                      'setobjs'		=> 1,
                      'top'		=> 1,
                      'powermeterlist'  => 1,
                      'tempmeterlist'   => 1,
                    );

# Dump the config object, resolving refs into human-readable (sort of) form:
sub dumpconf {
    my ($me, $name) = @_;

    my $dumper = new ConfigDumper([$me], ['*'.$name]);
    $dumper->Indent(1);
    $dumper->Translate([qw(config refs)]);
    $dumper->Refhash(\%refmapping);
    $dumper->Sortkeys(1);
    print $dumper->Dump;
}

# Load a file and merge it with the current data
sub merge {
    my ($me, $filename, $comment, $pp_macros, %opts) = @_;
    my ($include, $name, $value, @vals, $op);
    my @reflist = (reftype($opts{'reflist'}) eq 'ARRAY') ? @{$opts{'reflist'}} : ($me);
    my @tmpreflist = ();
    my $promote_to_header = 0;
    my @curr_sections = (reftype($opts{'curr_sections'}) eq 'ARRAY') ? @{$opts{'curr_sections'}} : ('header');
    my $continued = 0;
    my $appended = 0;
    my ($blockquote, $first_blockquote) = (undef, undef);
    my $eol_carp_done = 0;
    my @lastrefs = ();
    my %seen_extensions = (reftype($opts{'seen_extensions'}) eq 'HASH') ? %{$opts{'seen_extensions'}} : ( 'default' => 1, 'none' => 1 );
    # List of files read.  In the case of config files, it also lists our
    # parent files (if we're in an include chain).
    $me->{'files_read'} = [] unless (::reftype($me->{'files_read'}) eq 'ARRAY');
    # List of config files read.  This is used to keep track of which files
    # need to be included in bundles.
    $me->{'config_inc'} = {} unless (::reftype($me->{'config_inc'}) eq 'HASH');
    my $included = (@{$me->{'files_read'}}+0 > 0);
    my $tmppath = ($filename =~ m#^/#) ? $filename : jp($me->top, $me->configdir, $filename);
    my $sysinfo_run = 0;	# Have we run the system information program?
    my %sysinfo_dups = ();	# What settings did sysinfo stomp?
    my @pp_state = (1);		# 1 => include lines, 0 => don't
    my @pp_good = (1);		# Keep track of which nesting levels have true ifs
    $pp_macros = {} unless ref($pp_macros) eq 'HASH';
    $pp_macros->{'runspec'} = $me->runspec;
    my @bmlist = ('default', keys %{$me->{'benchsets'}},
		  map { $_->benchmark } values %{$me->{'benchmarks'}});
    my @tunelist = ('default', @{$me->{'valid_tunes'}});
    my $trimmedcomment = '';
    my $md5mode = 0;
    my (%sections, %variables);
    my %fixup_needed = (reftype($opts{'fixup_needed'}) eq 'HASH') ? %{$opts{'fixup_needed'}} : ();

    if (-f $tmppath) {
        # The name specified exists!  Yay!
        $filename = $tmppath;
    } else {
      # First try failed; does "$filename".cfg exist?
      if (-f $tmppath.'.cfg') {
        # Yes; use it
        $filename .= ".cfg";
        $filename = jp($me->top, $me->configdir, $filename) unless $filename =~ m#^/#;
      } else {
        if ($opts{'missing_ok'}) {
          # Don't complain about it.
          return 1;
        } else {
          # No.  Complain about it.
          if ($filename =~ m#^/#) {
              Log(100, "Neither config file '$filename' nor '${filename}.cfg' exist!\n");
          } else {
              Log(100, "Neither config file '$filename' nor '${filename}.cfg' exist in ".jp($me->top, $me->configdir)."!\n");
          }
          return 0;
        }
      }
    }

    # See if this is one of the default configs.
    if (!$::from_runspec &&
        (exists $::file_md5{$filename} ||
    	 ($^O =~ /MSWin/ && grep { /$filename/i } keys %::file_md5))) {
      my $warning = <<"EOW";

=============================================================================
Warning:  You appear to be using one of the config files that is supplied
with the SPEC $::suite distribution.  This can be a fine way to get started.

Each config file was developed for a specific combination of compiler / OS /
hardware.  If your platform uses different versions of the software or
hardware listed, or operates in a different mode (e.g. 32- vs. 64-bit mode),
there is the possibility that this configuration file may not work as-is. If
problems arise please see the technical support file at

  http://www.spec.org/$::lcsuite/Docs/techsupport.html

A more recent config file for your platform may be among result submissions at

  http://www.spec.org/$::lcsuite/ 

Generally, issues with compilation should be directed to the compiler vendor.
You can find hints about how to debug problems by looking at the section on
"Troubleshooting" in
  http://www.spec.org/$::lcsuite/Docs/config.html

This warning will go away if you rename your config file to something other
than one of the names of the presupplied config files.

==================== The run will continue in 30 seconds ====================
EOW
      Log(0, $warning);
      sleep 30;
    }

    # Break include loops
    if ($included &&
	grep { $_ eq $filename } @{$me->{'files_read'}}) {
	Log(100, "ERROR: include loop detected.  Here is the include chain:\n    ".
	    join("\n    ", (@{$me->{'files_read'}}, $filename))."\nIgnoring last entry - run will continue in 30 seconds.\n");
        sleep 30;       # Give them a chance to notice
	return 1;
    }

    $me->{'configpath'} = $filename unless $included;
    my $fh = new IO::File;
    if (!$fh->open($filename)) {
	Log(0, "ERROR: Can't read config file '$filename': $!\n");
	return 0;
    }
    push @{$me->{'files_read'}}, $filename;
    $me->{'config_inc'}->{$filename}++;

    Log(0, "Reading ".($included ? 'included ' : '')."config file '$filename'\n") unless ($::quiet || $::from_runspec);

    if (!$included) {
	$me->{'oldmd5'} =  '';
        my @stuff = (
          "# Invocation command line:",
          "# $0 ".join(' ', @{$me->{'orig_argv'}}),
          '# output_root was not used for this run',
          "############################################################################");
	$me->{'rawtxtconfigall'} = [ @stuff ];
	$me->{'rawtxtconfig'} = [ @stuff ];
	$me->{'pptxtconfig'} = [ @stuff ];
    }
    if ($comment ne '') {
	my @comments = map { "# $_" } split(/(?:\r\n|\n)/, $comment);
        push @comments, '############################################################################';
        foreach my $list (qw(pptxtconfig rawtxtconfig rawtxtconfigall)) {
            push @{$me->{$list}}, @comments;
        }
    }

    my ($cfline, @cflines) = (<$fh>);
    my $cflinenum = 1;
    while (defined($cfline)) {
        $cfline =~ tr/\012\015//d;

        # Strip unescaped trailing spaces
        $cfline =~ s/((?<!\\)\s)+$//g unless ($cfline =~ /^notes_wrap_indent/);
        # Strip escaping backslashes from trailing spaces
        $cfline =~ s/\\(\s)/$1/g;

	last if ($cfline =~ m/^__END__$/o);
	if ($cfline =~ m/^__MD5__$/o) {
	    if ($included) {
		last; # Ignore MD5 sections in included files
	    }
	    if ($sysinfo_run == 0) {
		unshift @cflines, "\n", $me->get_sysinfo(), $cfline;
	        $sysinfo_run = $cflinenum;
	    } else {
		$md5mode = 1;
	    }
	    $cfline = shift(@cflines);
            $cflinenum++;
	    next;
	}

        # Idiot guard
        if (!$::from_runspec &&
            !defined($blockquote) && !$continued && !$appended &&
            !$eol_carp_done && $cfline =~ m#^\s*([-/])#) {
          my $eol_carp = <<"EOCarp";

   =====================================================================
   Notice: Found a line at line number $cflinenum that starts with "$1"
            in "$filename":

$cfline

   This is not normally useful syntax in a SPEC $::suite config file.
   Have you perhaps passed a config file through a tool that
   thought it would be "helpful" to introduce an end-of-line
   character in the middle of a line that has a series of
   options?  (Some primitive email clients have been known to
   destroy technical content by doing so.)

   Only the first instance will receive this warning.  Lines
   like these will probably end up being ignored.

   Continuing in 10 seconds...
   =====================================================================

EOCarp
          ::Log(0, $eol_carp);
          $eol_carp_done = 1;
          sleep 10;
        }

	if ($md5mode) {
	    $me->{'oldmd5'} .= $cfline;
	} else {
	    # Save off this line but not protected comments that begin with '#>'
	    push @{$me->{'rawtxtconfigall'}}, $cfline;
	    if ($cfline =~ m/^\s*include:\s*\S+\s*$/i) {
		push @{$me->{'rawtxtconfig'}}, "#$cfline";
	    } elsif ($cfline !~ m/^\s*\#>/) {
		push @{$me->{'rawtxtconfig'}}, $cfline;
	    }
	}

        # Trim comments
	$trimmedcomment = '';
	# Bare # => comment; \# => #
	$trimmedcomment = $1 if ($cfline =~ s/(\s*(?<!\\)\#.*)//o);
        $cfline =~ s/\\\#/\#/og; # Unescape the escaped #

# XXX Protect temporarily against -DSPEC_CPU.* in config files
        if ($cfline =~ /DSPEC_CPU/) {
            Log(100, "\n\nERROR: There are no valid SPEC_CPU* defines in the codes!\nRemove all instances of -DSPEC_CPU<whatever> from your config file and try again.\n\nThis message posted by authority of J. Reilly, Sheriff.\n\n");
            do_exit(1);

        }
# XXX Protect temporarily against -DSPEC_CPU.* in config files

	# Do the preprocessor stuff
	if ($cfline =~ m/^%/o) {
	    if ($md5mode) {
		# No PP stuff in MD5 section
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
	    }
	    if ($cfline =~ m/^%\s*(warning|error|define|undef|ifdef|ifndef|else|elif|if|endif)\s*(.*?)\s*$/o) {
		my ($what, $rest) = (lc($1), $2);

		# Handle conditionals first.  Since we must pay attention for
		# %endif to end an exclusionary block, we also must pay
		# attention to %if and %ifdef so that one of _their_ %endifs
		# doesn't improperly end an enclosing block.
		if ($what eq 'endif') {
		    shift @pp_state;
		    if (@pp_state+0 <= 0) {
			Log(100, "ERROR: Unmatched %endif on line $cflinenum of $filename\n");
			do_exit(1);
		    }

		} elsif ($what eq 'ifdef' || $what eq 'ifndef') {
		    # Make it possible to do this the easy way
                    if ($rest !~ /^%/) {   # ...and catch the common mistake
                        Log(100, "WARNING: Syntax error in %$what conditional on line $cflinenum of\n         $filename; should be '%{$rest}'\n");
		    } else {
                      $rest =~ /^(?<!\\)%\{([^%\{\}]+)\}/;
                      if ($1 ne '') {
                          # A simple match -- handle it
                          $rest = $1;
                      } else {
                          # Nested references... grr.  Try stripping off
                          # surrounding %{...} and then expanding it.
                          $rest =~ s/^(?<!\\)%\{//;
                          $rest =~ s/\}[^\}]*$//;
                          my $tmp = pp_macro_expand($rest, $pp_macros, 0, 0, $filename, $cflinenum, 1);
                          $rest = $tmp if defined($tmp) && $tmp ne '';
                      }
                    }
                    my $rc = istrue(exists($pp_macros->{$rest}));
		    $rc = 1 - $rc if $what eq 'ifndef';
		    unshift @pp_state, $pp_state[0] ? $rc : 0;
		    $pp_good[$#pp_state] = $pp_state[0];

		} elsif ($what eq 'else') {
		    shift @pp_state;
		    unshift @pp_state, $pp_good[$#pp_state + 1] == 0 ? $pp_state[0] : 0;
		    # Set this so that if someone puts _more_ else or elif
		    # blocks after that they don't get executed.
		    $pp_good[$#pp_state] = 1;

		} elsif ($what eq 'elif') {
		    # Only evaluate the %elif if no other blocks have been true
		    shift @pp_state;
                    my $new_state = 0;
                    if ($pp_good[$#pp_state + 1] == 0 && $pp_state[0] == 1) {
                        $new_state = eval_pp_conditional($rest, $pp_macros, $filename, $cflinenum);
                    }
                    unshift @pp_state, $new_state;
		    $pp_good[$#pp_state] = $pp_state[0] if (!$pp_good[$#pp_state]);

		} elsif ($what eq 'if') {
		    unshift @pp_state, $pp_state[0] ? eval_pp_conditional($rest, $pp_macros, $filename, $cflinenum) : 0;
		    $pp_good[$#pp_state] = $pp_state[0];
		}

		# If we're currently excluding lines, don't go any further in
		# order to avoid processing any directives that shouldn't be
		# seen.
		if (!$pp_state[0]) {
		    $cfline = shift(@cflines);
		    $cflinenum++;
		    next;
		}

		if ($what eq 'define') {
		    my ($symbol, $value) = $rest =~ m/(\S+)\s*(.*)/;
                    $value = '' if (!defined($value) || ($value eq ''));

                    # Restrict macro names to alphanumerics
                    if ($symbol !~ /^[A-Za-z0-9_-]+$/) {
                        Log(100, "\n",
                                 "*************************************************************************\n",
                                 "  ERROR: Macro names may contain only alphanumeric characters, underscores,\n",
                                 "         and hyphens.\n",
                                 "         Bad macro name \"$symbol\" on line $cflinenum of\n",
                                 "         $filename\n",
                                 "*************************************************************************\n",
                                 "\n");
                        do_exit(1);
                    }

                    if ($symbol =~ m/^%{(.*)}$/) {
                        $symbol = $1;
                        Log(100, "Notice: Macro names should not be enclosed in '%{}' for definition.\n");
                        Log(100, "        Attempting to do the right thing on line $cflinenum of $filename\n");
                    }

		    if (exists ($pp_macros->{$symbol})) {
			Log(100, "WARNING: Redefinition of preprocessor macro '$symbol' on line $cflinenum\n         of $filename\n");
		    }
		    $pp_macros->{$symbol} = $value;

		} elsif ($what eq 'undef') {
                    if ($rest =~ /%\{/) {
                        # Run it through macro expansion to get the symbol to
                        # undefine
                        my $orig = $rest;
                        $rest = pp_macro_expand($rest, $pp_macros, 0, 0, $filename, $cflinenum, 1);
                        $rest = $orig unless (defined($rest) && $rest ne '');
                        Log(15, "Macro undef: \"$orig\" expanded to \"$rest\"\n");
                    }
		    if (exists ($pp_macros->{$rest})) {
			delete $pp_macros->{$rest};
		    } else {
			Log(100, "ERROR: Can't undefine nonexistent symbol '$rest' on line $cflinenum\n       of $filename\n");
		    }
		} elsif ($what eq 'warning') {
		    Log(100, "\n",
                             "****\n",
                             'WARNING: '.pp_macro_expand($rest, $pp_macros, 0, 0, $filename, $cflinenum, 1)." on line $cflinenum\n         of $filename\n",
                             "****\n",
                             "\n");
		} elsif ($what eq 'error') {
		    Log(100, "\n",
                             "*************************************************************************\n",
                             '  ERROR: '.pp_macro_expand($rest, $pp_macros, 0, 0, $filename, $cflinenum, 1)." on line $cflinenum\n         of $filename\n",
                             "*************************************************************************\n",
                             "\n");
		    do_exit(1);
		}
		# We've handled the preprocessor directive; start over.
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
	    } else {
                $cfline =~ m/^(%\s*\S+)/o;
		Log(100, "ERROR: Unknown preprocessor directive: \"$1\" on line $cflinenum\n");
		Log(100, "       of $filename\n");
		do_exit(1);
            }
	}
	elsif ($cfline =~ m/^\s+%\s*(warning|error|define|undef|ifdef|ifndef|else|elif|if|endif)/o) {
            Log(100, "\nWARNING: Ignoring preprocessor directive \"$1\" with leading whitespace\n");
            Log(100, "         on line $cflinenum of $filename.\n\n");
        }

	# Here's the main place where we skip stuff if we're in an
	# exclusionary block.
	if (!$pp_state[0] && !$md5mode) {
	    $cfline = shift(@cflines);
            $cflinenum++;
	    next;
	}

	# Expand any macros that may be present
	if (!$md5mode) {
	    $cfline = pp_macro_expand($cfline, $pp_macros, 0, 0, $filename, $cflinenum, 1);
	    my $tmpstr = $cfline;
	    my $cnt = $tmpstr =~ tr/\015\012//d;
	    $tmpstr .= $trimmedcomment;
            # Put "comments" back on notes lines
            if ($cfline =~ /^$::mpi_desc_re_id?notes/io) {
                $cfline .= $trimmedcomment;
            }
	    if ($cfline =~ m/^\s*include:\s*\S+\s*$/i) {
		$tmpstr = "#$tmpstr";
	    }
            push @{$me->{'pptxtconfig'}}, $tmpstr;
            push @{$me->{'pptxtconfig'}}, '' if $cnt;
	}

	# Handle <<EOT type blocks in config file
	if (defined $blockquote) {
	    if ($cfline eq $blockquote) {
		undef $blockquote;
	    } elsif ($first_blockquote) {
		map { $$_ .= $cfline } @lastrefs;
		$first_blockquote=0;
	    } else {
		map { $$_ .= "\n$cfline" } @lastrefs;
	    }

	# Handle continued lines with '\' at end of line
	} elsif ($continued) {
	    $continued = 0;
	    $appended = 1 if ($cfline =~ s/\\\\$//);
	    $continued = 1 if ($cfline =~ s/\\$//);
            foreach my $lastline (@lastrefs) {
                if ($$lastline ne '') {
                    $$lastline .= "\n$cfline";
                } else {
                    # Don't prepend a newline to empty lines
                    $$lastline .= $cfline;
                }
            }

        # Handle appended lines with '\\' at end of line
	} elsif ($appended) {
            $cfline =~ s/^\s+//;
	    $appended = 0;
	    $appended = 1 if ($cfline =~ s/\\\\$//);
	    $continued = 1 if ($cfline =~ s/\\$//);
            foreach my $lastline (@lastrefs) {
                if ($$lastline ne '') {
                    $$lastline .= " $cfline";
                } else {
                    # Don't prepend a space to empty lines
                    $$lastline .= $cfline;
                }
            }
            # Fix up the lines that were just present; doing this here
            # avoids lots of nastiness in the raw file parser.
            foreach my $list (qw(pptxtconfig rawtxtconfig rawtxtconfigall)) {
                pop @{$me->{$list}};
                if ($me->{$list}->[$#{$me->{$list}}] ne '') {
                    $me->{$list}->[$#{$me->{$list}}] .= " $cfline";
                } else {
                    # Don't prepend a space to empty lines
                    $me->{$list}->[$#{$me->{$list}}] .= $cfline;
                }
            }

        # Include a file
	} elsif (($include) = $cfline =~ m/^\s*include:\s*(\S+)\s*$/i) {
            if ($include =~ m/\$[\[\{]([^\}]+)[\}\]](\S*)\s*$/) {
		my ($tmpname, $rest) = ($1, $2);
                if ($tmpname =~ s/^ENV_//) {
                    $include = $ENV{$tmpname}.$rest;
                } else {
                    $include = $me->{$tmpname}.$rest;
                }
	    }
            @{$opts{'reflist'}} = @reflist;
            @{$opts{'curr_sections'}} = @curr_sections;
            %{$opts{'seen_extensions'}} = %seen_extensions;
            %{$opts{'sections'}} = %sections;
            %{$opts{'fixup_needed'}} = %fixup_needed;
	    if (! $me->merge($include, " ----- Begin inclusion of '$include'",
			     $pp_macros, %opts)) {
		Log(100, "Can't include file '$include'\n");
		do_exit(1);
	    }
            @reflist = @{$opts{'reflist'}};
            @curr_sections = @{$opts{'curr_sections'}};
            %seen_extensions = %{$opts{'seen_extensions'}};
            %sections = %{$opts{'sections'}};
            %fixup_needed = %{$opts{'fixup_needed'}};

	# Check to see if the line is in the form of x=x=x=x: or some subset.
	# if so, then point the working reference pointer at that data.
	} elsif ((@vals) = $cfline =~
	    m/^\s*([^\#=\s]+)(?:=([^=\s]+))?(?:=([^=\s]+))?(?:=([^=\s]+))?:\s*$/o) {
	    for (my $i = 0; $i < 4; $i++) {
		if (!defined($vals[$i]) || $vals[$i] eq '') {
		    $vals[$i] = [ 'default' ];
		    $sections{'default'}++;
		    next;
		}
		if ($vals[$i] =~ /:/o) {
		    Log(100, "':' is not allowed in a section name:\n '$vals[$i]' in '$cfline'\n");
		    $vals[$i] =~ s/://go;
		} elsif ($vals[$i] =~ /,/o) {
		    # Handle multiple values, and make sure they're unique
		    $vals[$i] = [ uniq(map { (defined($_) && ($_ ne '')) ? $_ : 'default' } split(/,/, $vals[$i])) ];
		} else {
		    $vals[$i] = [ $vals[$i] ];
		}
	    }
	    my ($bench, $tune, $ext, $mach) = @vals;
	    @reflist = ();
	    @curr_sections = ();
	    foreach my $tb (@$bench) {
		$sections{$tb}++;
		if (!grep { $tb eq $_ } @bmlist) {
                    next if $md5mode;
		    Log(100, "ERROR: Unknown benchmark \'$tb\' specified on line $cflinenum\n       of $filename");
		    if (istrue($me->{'section_specifier_fatal'}) &&
                        !istrue($me->{'ignore_errors'})) {
			Log(100, "\n");
			do_exit(1);
		    } else {
			Log(100, "; ignoring\n");
			$::keep_debug_log = 1;
			next;
		    }
		}
		foreach my $tt (@$tune) {
		    $sections{$tt}++;
		    if (!grep { $tt eq $_ } @tunelist) {
                        next if $md5mode;
			Log(100, "ERROR: Unknown tuning level \'$tt\' specified on line $cflinenum\n       of $filename");
			if (istrue($me->{'section_specifier_fatal'})) {
			    Log(100, "\n");
			    do_exit(1);
			} else {
			    Log(100, "; ignoring\n");
			    next;
			}
		    }
		    foreach my $te (@$ext) {
                        $seen_extensions{$te}++;
			$sections{$te}++;
			foreach my $tm (@$mach) {
			    $sections{$tm}++;
			    $me->ref_tree(basename(__FILE__).':'.__LINE__,
					  [$tb],[$tt],[$te],[$tm]);
			    add_refs($me, $tb, $tt, $te, $tm);
			    push @reflist, $me->{$tb}{$tt}{$te}{$tm};
			    push @curr_sections, "${tb}=${tt}=${te}=${tm}";

			}
		    }
		}
	    }

        # Named pairs to current working reference
        # "src.alt" gets a special mention because I don't want to allow
        # periods in all variable names.
	} elsif (($name, $op, $value) = $cfline =~ m/^\s*([A-Za-z0-9_]+|src\.alt)\s*(\+\=|\=)(.*)/) {

            $name = 'srcalt' if $name eq 'src.alt';
            if ($op eq '+=' && ($name =~ /$::info_re/ || 
				defined($::default_config->{$name}) || 
				defined($::nonvolatile_config->{$name}) ||
				$name =~ /submit|bind|srcalt|power_analyzer|temp_meter|notes/)
		) {		
		::Log(0, "ERROR: Concatenation (+=) is not allowed for \"$name\" on line $cflinenum\n         of $filename. \n");
		do_exit(1);
	    }

	    $variables{$name}++;
	    # Check for and remove nonvolatile config options if necessary
	    # Just in case there has been an oversight and a nonvolatile
	    # option has been inserted into the list of command line options,
	    # throw it out and issue a warning.
	    if (exists($::nonvolatile_config->{$name})) {
		Log(100, "WARNING: The value for \"$name\" is immutable.  Illegal attempt to change\n         it on line $cflinenum of $filename; ignoring\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
	    }

            # Ditto for internal stuff
	    if (exists($::reserved_words{$name}) ||
                $name =~ /^cfidx_/) {
		Log(100, "WARNING: \"$name\" is reserved for use by runspec.\n         Ignoring contents of line $cflinenum in $filename\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
	    }

            # Not-so-quietly ignore settings for test_date; it's now set
            # automatically, but may be edited in the raw file.
            if ($name eq 'test_date') {
		Log(100, "WARNING: The value for \"test_date\" is set automatically from the system\n         clock.  If necessary, the value may be changed in the raw file after\n         the run.\n");
                Log(100,"        The settings on line $cflinenum of $filename\n         will be ignored.\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
            }

            # Not-so-quietly ignore settings for sw_auto_parallel; it's now set
            # automatically, and no longer appears in the raw file
            if (   $::lcsuite ne 'mpi2007'
                && $name eq 'sw_auto_parallel') {
		Log(100, "WARNING: The field \"sw_auto_parallel\" has been retired.  Please see \n\n");
                Log(100, "              http://www.spec.org/$::lcsuite/Docs/config.html#parallelreporting\n\n");
                Log(100, "         for more information on how to indicate whether\n");
                Log(100, "         or not automatic parallelization is used.\n");
                Log(100,"        The settings on line $cflinenum of $filename\n         will be ignored.\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
            }

            # Not-so-quietly ignore settings for sw_parallel_defeat; it may
            # only be set in the raw file
            if ($name eq 'sw_parallel_defeat') {
		Log(100, "WARNING: The field \"sw_parallel_defeat\" may only be set in the raw file.\n");
                Log(100,"        The settings on line $cflinenum of $filename\n         will be ignored.\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
            }

            # Don't allow the user to set NC-related variables in the config
            # file.
            if ($name =~ /^(nc\d*|nc_is(?:cd|na))$/) {
		Log(100, "ERROR: You may not set reasons for non-compliance, non-availability, or\n");
                Log(100, "       code defect in the config file.  The setting for \"$name\" on\n");
                Log(100, "       line $cflinenum of $filename will be ignored\n");
		$cfline = shift(@cflines);
                $cflinenum++;
		next;
	    }

            # Check for and remove options that must be set in the header
            # section, unless one of the current refs is
            # default=default=default=default, in which case silently put it
            # in the header section and ignore the others.
            my $nonumname = $name;
            $nonumname =~ s/\d+$//;
            if ($reflist[0] != $me &&
                (exists($::header_only{$name}) ||
                 exists($::header_only{$nonumname}))) {
                if (grep { /^default=default=default=default$/ } @curr_sections) {
                    # Temporarily set the whole reflist to just the top-level
                    $promote_to_header = 1;
                    @tmpreflist = @reflist;
                    @reflist = ( $me );
                } else {
                    Log(100, "\nWARNING: \"$name\" may be set only in the header section of the config file.\n");
                    if (@curr_sections > 1) {
                        Log(100, "  Current sections are ".join("\n                       ", @curr_sections)."\n");
                    } else {
                        Log(100, "  Current section is $curr_sections[0]\n");
                    }
                    Log(100, "Ignoring the setting on line $cflinenum of $filename.\n\n");
                    sleep 3;
                    $cfline = shift(@cflines);
                    $cflinenum++;
                    next;
                }
            }

	    # Everything except notes should have leading whitespace removed
	    $value =~ s/^\s*//o unless ($name =~ /^$::mpi_desc_re_id?notes/io);

	    # I've promised that ext, mach, iterations, and bind can be
            # explicitly multi-valued.  But (except for iterations and bind),
            # they can't be set within a benchmark section, and iterations
            # can't be multi-valued in that context.
	    if ($name =~ /^(ext|mach|iterations|output_root|expid|flagsurl|temp_meter|power_analyzer|platform|device)$/) {
		my $what = lc($1);
                if ($what =~ /^(ext|mach)$/ && $value !~ /^[A-Za-z0-9_., -]+$/) {
                    Log(100, "ERROR: Illegal characters in '$what'; on line $cflinenum\n       of $filename; please use only alphanumerics,\n");
                    Log(100, "       underscores (_), hyphens (-), and periods (.).\n");
                    ::do_exit(1);
                }
		if ($reflist[0] != $me) {
		    if ($what =~ /^(?:ext|mach|output_root|expid|flagsurl|temp_meter|power_analyzer|platform|device)$/) {
			Log(100, "ERROR: '$what' (line $cflinenum of $filename)\n       may only appear before the first section marker!\n");
                        ::do_exit(1);
		    } elsif ($what eq 'iterations' && $value =~ /,/) {
			Log(100, "Notice: per-benchmark iterations cannot be multi-valued! Ignoring setting\n        on line $cflinenum of $filename.\n");
			$cfline = shift(@cflines);
		        $cflinenum++;
			next;
		    }
		}
	    }

	    # If it is the special case %undef% then remove the specified keys
	    # from the working reference and replace them with the special
            # %undef% tag to block down-tree references
	    if ($value =~ m/^\s*%undef%\s*$/io) {
		foreach my $ref (@reflist) {
		    for my $key (find_keys($ref, $name)) {
			if (exists($ref->{$key})) {
                          delete $ref->{$key};
                          $ref->{$key} = '%undef%';
                        }
		    }
		    $ref->{$name} = '%undef%';
		}
	    } elsif (!$md5mode &&
		     ($name eq 'optmd5' || $name eq 'exemd5' ||
		      $name eq 'compile_options' || $name eq 'baggage' ||
		      $name eq 'raw_compile_options')) {
		$cfline = shift(@cflines);
		$cflinenum++;
		next;
	    } elsif ($name eq 'rawtxtconfig' || $name eq 'rawtxtconfigall' ||
		     $name eq 'pptxtconfig' || $name =~ /^cfidx_/) {
		$cfline = shift(@cflines);
		$cflinenum++;
		next; # We don't allow people to overwrite the stored configs

	    } elsif ($name eq 'inherit_from') {
		# inherit_from is special because it's allowed to be
		# implicitly multi-valued.
		my @reftrees = ();
                # Strip whitespace from $value.  Section name components can't
                # have any, so it doesn't make sense for there to be any in
                # here, either.
                $value =~ s/\s+//g;
		foreach my $ancestor (split(/,+/, $value)) {
		    push @reftrees, $me->ref_tree('', map { [ (defined($_) && $_ ne '') ? $_ : 'default' ] } (split(/:/, $ancestor))[0..3]);
		}
		foreach my $ref (@reflist) {
		    if (exists($ref->{'inherit_from'}) &&
			ref($ref->{'inherit_from'}) eq 'ARRAY') {
			push @{$ref->{'inherit_from'}}, @reftrees;
		    } else {
			$ref->{'inherit_from'} = [ @reftrees ];
		    }
		}

	    } elsif ($name =~ /^hw_ncpu$/) {
		# hw_ncpu is special because it's likely to appear in
                # (old) config files, but we construct it from other
                # things, so it should be ignored.
                ::Log(0, "\nWARNING: hw_ncpu setting on line $cflinenum of\n");
                ::Log(0, "         $filename is ignored.\n");
                ::Log(0, "         Please set values individually using hw_nchips, hw_ncores,\n");
                ::Log(0, "         hw_ncoresperchip, and hw_nthreadspercore.\n\n");

	    } else {


                # In order to make things VASTLY simpler in Makefile.defaults,
                # fix up ONESTEP here.  The intent is to turn No, False, 0,
                # etc. into an empty value.
                if ($name =~ /ONESTEP$/) {
                    $value = istrue($value) ? 1 : '';
                }

		if ($value=~ s/^\s*<<\s*(\S+)\s*$//) {
		    $blockquote = $1;
		    $first_blockquote = 1;
		    $value = '';
		} elsif ($value=~ s/\\\\\s*$//) {
		    $appended  = 1;
                    # Trim this from the saved line as well.
                    foreach my $list (qw(pptxtconfig rawtxtconfig rawtxtconfigall)) {
                        $me->{$list}->[$#{$me->{$list}}] =~ s/\\\\\s*$//;
                    }
		} elsif ($value=~ s/\\\s*$//) {
		    $continued  = 1;
		}

                if ($name eq 'ext') {
                  # If it's ext, mark it down as 'seen'
                  $seen_extensions{$value}++;
                }

		@lastrefs = ();
		foreach my $ref (@reflist) {
                    
                    if ($name =~ /^ ?(bind|srcalt|power_analyzer|temp_meter)(\d*)$/) {
                        my ($base, $idx) = ($1, $2);
                        # Keep track of which refs need fixups, and
                        # also which line numbers the settings came
                        # from.  This is to allow "overwrite" warnings
                        # if necessary.
                        $name = " $base" if ($idx eq '');
                        $fixup_needed{$base}->{$ref}->{'ref'} = $ref;
                        push @{$fixup_needed{$base}->{$ref}->{'pairs'}}, [ $name, $filename, $cflinenum ];
                    }

                    $ref->{'copylist'} = [ split(/,+|\s+/, $value) ] if ($name eq 'copies');
                    if ($name eq 'submit') {
                      # This'll get fixed up later
                      $name = 'submit_default';
                    }

                    # Deal with the order for MPI stuff
                    if ($name =~ /^$::mpi_desc_re/) {
                        my ($type, $which) = ($1, $2);
                        if (!exists($ref->{"${type}_${which}_order"})) {
                            $ref->{"${type}_${which}_order"} = 0;
                        }
                    }

		    if ($op eq '+=') {
			if (defined($ref->{$name})) {
			    if ((reftype($ref->{$name}) eq 'HASH') && $ref->{$name}->{'op'} eq '+=') {
				$ref->{$name}->{value} .= " $value";
			    } else {
				$ref->{$name} .= " $value";
			    }
		        } else {
			    $ref->{$name} = {};
			    $ref->{$name}->{'value'} = $value;
		     	    $ref->{$name}->{'op'} =  '+=';
                        } 
		    } else {
			$ref->{$name} = $value;
		    } 
                    if ($name =~ /$::info_re/) {
                        if (exists($ref->{'cfidx_'.$name})) {
                            if ($sysinfo_run == 0) {
                                ::Log(0, "WARNING: Duplicate setting for \"$name\" on line $cflinenum\n         of $filename\n");
                            } else {
                                push @{$sysinfo_dups{$name}}, ($cflinenum - $sysinfo_run);
                            }
                        }
                        $ref->{'cfidx_'.$name} = $#{$me->{'rawtxtconfig'}};
                    }
                    push @lastrefs, \$ref->{$name};

                    if ($promote_to_header) {
                        # Remove the temporary override of the reflist
                        @reflist = @tmpreflist;
                        $promote_to_header = 0;
                    }
		}
	    }
	} elsif (!$appended && !$continued && !defined($blockquote) &&
                 $cfline !~ /^\s*$/) {
            ::Log(0, "Notice: Ignored non-comment line in file $filename:\n  line $cflinenum: \"$cfline\"\n");
        }
	$cfline = shift(@cflines);
	$cflinenum++;
	if (!$included && !defined($cfline) && ($sysinfo_run == 0)) {
	    # We're to the end of the file... is there a sysinfo program?
	    push @cflines, $me->get_sysinfo();
	    $cfline = "\n";
	    $sysinfo_run = $cflinenum;
            $filename = 'sysinfo output';
	}
    }

    if ($sysinfo_run && %sysinfo_dups) {
        if (0) {
            # Long form output, with probably useless line numbers
            my @dupnames = sort { length($b) <=> length($a) } keys %sysinfo_dups;
            my $namelen = length($dupnames[0]);
            $namelen = 10 unless $namelen >= 10;
            ::Log(0, "\n\nWARNING: Your config file sets some fields that are also set by sysinfo.\n");
            ::Log(0, sprintf "\t%*s\tsysinfo output line\n", -$namelen, "Field name");
            ::Log(0, sprintf "\t%*s\t-------------------\n", -$namelen, "----------");
            foreach my $dupname (sort @dupnames) {
                ::Log(0, sprintf "\t%*s\t%s\n", -$namelen, $dupname, join(', ', @{$sysinfo_dups{$dupname}}));
            }
        } else {
            # Short form output; fields only
            ::Log(0, "\n\nWARNING: Your config file sets some fields that are also set by sysinfo:\n");
            foreach my $fieldlist (::wrap_lines([join(', ', sort keys %sysinfo_dups)], 73, '')) {
                ::Log(0, "  $fieldlist\n");
            }
        }
        ::Log(0, "To avoid this warning in the future, see\n");
        ::Log(0, "  http://www.spec.org/$::lcsuite/Docs/config.html#sysinfo\n\n\n");
    }

    if ($blockquote) {
        ::Log(0, "ERROR: Unterminated block quote in $filename; '$blockquote' not found\n");
        ::do_exit(1);
    }

    if ($included) {
	my $eos = "# ---- End inclusion of '$filename'";
	push @{$me->{'rawtxtconfigall'}}, $eos;
	push @{$me->{'rawtxtconfig'}}, $eos;
	push @{$me->{'pptxtconfig'}}, $eos;
    } else {
        # Fix up items that become lists.  This includes srcalt and bind.
        # The idea is to walk through the elements that WOULD contribute to
        # the single value.  In these cases, they can be set all at once (as in
        # "bind = 1 2 4 foo"), or one by one (as in "bind0 = 1; bind1 = 2").
        # The objective is to end up with one element per ref, which will be
        # an array, and with all of the "contributing" items and their cfidx
        # deleted.
        if (exists($fixup_needed{'srcalt'})) {
            # srcalt is special because it's allowed to be
            # implicitly or explicitly multi-valued, and all values for a
            # particular section must be unique.
            foreach my $section (keys %{$fixup_needed{'srcalt'}}) {
                # Go through each key that was added and apply it to the
                # final value.
                my $ref = $fixup_needed{'srcalt'}->{$section}->{'ref'};
                my $final = undef;
                $final = $ref->{'srcalt'} if (reftype($ref->{'srcalt'}) eq 'ARRAY');
                my %kill_keys = ();
                foreach my $pair (@{$fixup_needed{'srcalt'}->{$section}->{'pairs'}}) {
                    my ($name, $file, $line) = @{$pair};
                    my $value = $ref->{$name};
                    $value =~ s/^\s+//;
                    $kill_keys{$name} = 1;

                    my @srcalts = grep { defined && !/%undef%/i } split(/[\s,]+/, $value);
                    undef $final if ($value =~ /%undef%/i);
                    if (!defined($final) || (reftype($final) ne 'ARRAY')) {
                        $final = [];
                    }
                    my %seensrcalts = map { $_ => 1 } @{$final};
                    foreach my $srcalt (@srcalts) {
                        next if $seensrcalts{$srcalt}++;
                        push @{$final}, $srcalt;
                    }
                }
                foreach my $key (keys %kill_keys) {
                    delete $ref->{$key};
                    delete $ref->{'cfidx_'.$key} if exists($ref->{'cfidx_'.$key});
                }
                $ref->{'srcalt'} = [ @{$final} ];   # Get a new ref
            }
        }

        # See the comments before the 'srcalt' block above to find out what's
        # going on here.
        foreach my $thing ('bind', 'power_analyzer', 'temp_meter') {
            # These things are special because they're allowed to be
            # implicitly or explicitly multi-valued, and order is important.
            if (exists($fixup_needed{$thing})) {
                my %change_count;
                foreach my $section (keys %{$fixup_needed{$thing}}) {
                    # Go through each key that was added and apply it to the
                    # final value.
                    my $ref = $fixup_needed{$thing}->{$section}->{'ref'};
                    my $final = undef;
                    $final = $ref->{$thing} if (reftype($ref->{$thing}) eq 'ARRAY');
                    my %kill_keys = ();
                    foreach my $pair (@{$fixup_needed{$thing}->{$section}->{'pairs'}}) {
                        my ($name, $file, $line) = @{$pair};
                        my $value = $ref->{$name};
                        $kill_keys{$name} = 1;
                        my $idx = undef;
                        if ($name =~ /^(?:power_analyzer|temp_meter|bind)(\d+)/) {
                            $name = $thing;
                            $idx = $1;
                        }
                        $change_count{$section}++;

                        if (!defined($idx) || $idx eq '') {
                            # Implicitly multi-valued
                            $value =~ s/^\s+//;
                            my @values = split(/[\n\s,]+/, $value);
                            ::Log(0, "Notice: $thing setting on line $line of $file\n        will override previously set value\n") if ($change_count{$section} > 1);
                            $final = [ @values ];
                        } else {
                            $idx = $idx + 0;	# Make it a proper number
                            $final->[$idx] = $value;
                        }
                    }
                    foreach my $key (keys %kill_keys) {
                        delete $ref->{$key};
                        delete $ref->{'cfidx_'.$key} if exists($ref->{'cfidx_'.$key});
                    }
                    $ref->{$thing} = [ @{$final} ];   # Get a new ref
                }
            }
        }

	# Make sure all of the benchmark sections have 'refs'
	foreach my $tb (@bmlist) {
	    next unless (exists($me->{$tb}) && ref($me->{$tb}) eq 'HASH');
	    my $ref = $me->{$tb};
	    foreach my $tt (sort keys %{$ref}) {
		next unless (exists($ref->{$tt}) && ref($ref->{$tt}) eq 'HASH');
		$ref = $ref->{$tt};
		foreach my $te (sort keys %{$ref}) {
		    next unless (exists($ref->{$te}) && ref($ref->{$te}) eq 'HASH');
		    $ref = $ref->{$te};
		    foreach my $tm (sort keys %{$ref}) {
			next unless (exists($ref->{$tm}) && ref($ref->{$tm}) eq 'HASH');
			add_refs($me, $tb, $tt, $te, $tm);
		    }
		}
	    }
	}

#	$me->dumpconf('initial_config'); exit;
	$me->expand_vars();

        # And make sure that the flagsurl is set properly
        if (   exists($me->{'flagsurl'})
            && (reftype($me->{'flagsurl'}) ne 'ARRAY')
            && $me->{'flagsurl'} ne '') {
            $me->{'flagsurl'} = [ $me->{'flagsurl'} ];
        } else {
            $me->{'flagsurl'} = [ ];
        }
        # Process flags URLs in reverse order so that multiples specified on
        # the same line will end up in the right order (and not overwritten
        # by later settings)
        foreach my $item (reverse sort ::bytrailingnum grep { /^flagsurl\d*$/ } keys %{$me}) {
            my ($idx) = ($item =~ m/^flagsurl(\d*)$/);
            if (@{$me->{'flagsurl'}} < $idx) {
                # Grow the array if necessary
                $me->{'flagsurl'}->[$idx] = undef;
            }
            my @urls = split(/[,\s]+/, join(',', ::allof($me->{$item})));
            splice(@{$me->{'flagsurl'}}, $idx, 1, @urls);
        }
        ::squeeze_undef($me->{'flagsurl'});

#	$me->dumpconf('expanded_config'); exit;

    }

    # Check for conflicts between variable names (including nonvolatile
    # and default config) and section names.  First, the stuff we know about:
    my $conflicts = '';
    foreach my $section (sort keys %sections) {
	if (exists($::nonvolatile_config->{$section})) {
	    $conflicts .= " Section name '$section' (".pluralize($sections{$section}, 'occurrence').")\n  conflicts with the name of a non-volatile variable.\n";
	} elsif (exists($::default_config->{$section})) {
	    $conflicts .= " Section name '$section' (".pluralize($sections{$section}, 'occurrence').")\n  conflicts with the name of a default variable.\n";
	} elsif (exists($variables{$section})) {
	    $conflicts .= " Variable name '$section' (".pluralize($variables{$section}, 'occurrence').")\n  conflicts with section name (".pluralize($sections{$section}, 'occurrence').")\n";
	}
    }
    if ($conflicts ne '') {
	Log(100, "ERROR:  Variable/section name conflicts detected:\n\n");
	Log(100, $conflicts);
	do_exit(1);
    }

    if (istrue($me->{'build_in_build_dir'})) {
        $me->{'builddir'} = 'build';
    } else {
        $me->{'builddir'} = 'run';
    }

    if ($included) {
      # Put the opts back
      @{$opts{'reflist'}} = @reflist;
      @{$opts{'curr_sections'}} = @curr_sections;
      %{$opts{'seen_extensions'}} = %seen_extensions;
      %{$opts{'sections'}} = %sections;
      %{$opts{'fixup_needed'}} = %fixup_needed;
      # Without this, multiple inclusion of the same file will fail.
      pop @{$me->{'files_read'}};
    } else {
        # Make the stored config texts back into strings
        foreach my $list (qw(pptxtconfig rawtxtconfig rawtxtconfigall)) {
            my $tmp = join("\n", @{$me->{$list}})."\n";
            $me->{$list} = $tmp;
        }

        # Store away the list of seen extentions
        $me->{'seen_extensions'} = \%seen_extensions;

        # Add the list of config files seen to the list of files read
        map { delete $me->{'config_inc'}->{$_} } @{$me->{'files_read'}};
        push @{$me->{'files_read'}}, sort keys %{$me->{'config_inc'}};
        delete $me->{'config_inc'};
    }

    $fh->close();

    if (@pp_state > 1) {
        Log(100, "ERROR: Unbalanced %if .. %endif in $filename\n");
        do_exit(1);
    }

    1;
}

sub add_refs {
    my ($ref, $tb, $tt, $te, $tm) = @_;

    my @sets = $ref->benchmark_in_sets($tb);
    my $tmpref = $ref->{$tb}{$tt}{$te}{$tm};
    if (exists($tmpref->{'refs'})) {
#	print "add_refs: refs for $tb:$tt:$te:$tm already exist:\n";
#	dumpconf($tmpref);
	return;
    }

    # Set up refs so that variable interpolation can be
    # performed.  This value will be blown away after
    # variable expansion so that there's no danger of
    # using a local copy of refs to get back to the
    # data in global_config.
    $tmpref->{'ref_added'} = basename(__FILE__).':'.__LINE__;
    $tmpref->{'refs'} = [ $tmpref,
			  reverse ($ref,
				   $ref->ref_tree(basename(__FILE__).':'.__LINE__,
						  ['default', @sets, $tb],
						  ['default', $tt],
						  ['default', $te],
						  ['default', $tm])) ];
}

sub expand_vars {
    # This handles the first pass of runspec variable substitution (aka
    # "square bracket" substitution).  The work is done in config_var_expand().
    my ($me) = @_;

    return if ref($me) !~ /^(?:HASH|Spec::Config)$/;

    # At this point, all of the sections' refs fields are filled in... do
    # the promised expansion
    foreach my $member (sort keys %{$me}) {
	# There are some settings which should not have variable expansion
	# applied
	next if (exists($::nonvolatile_config->{$member}) ||
		 $member =~ /(?:txtconfig$|^orig_|^ref|^bench(?:mark|set)s)/o);
	if (ref($me->{$member}) ne '') {
	    if (ref($me->{$member}) eq 'HASH') {
		expand_vars($me->{$member});
		delete ($me->{$member}->{'refs'});
	    }
	} else {
	    $me->{$member} = config_var_expand($me->{$member}, $me, 1);
	}
    }
}

sub eval_pp_conditional {
    my ($text, $macros, $file, $linenum) = @_;

    # Resolve the values of all the macros in the line.
    $text = pp_macro_expand($text, $macros, 0, 1, $file, $linenum, 0);
    # In a construction like
    #    %if defined(%{foo})
    # where 'foo' is undefined, the resulting expression is
    #    defined()
    # which Perl very much does not like.  So fix it up, like this:
    $text =~ s/defined\((?:'')?\)/defined(undef)/g;

    if ($text eq '') {
	# It could happen
	return 0;
    } else {
	my $compartment = new Safe;
	$compartment->permit_only(qw(:base_core :base_math));
	# What we're really after here are the Perl math and boolean operations
	# There shouldn't be anything like a variable in there at this point,
	# so (among other things) disallow variable references.
	$compartment->deny(qw(aelem aelemfast aslice av2arylen rv2av
			      helem hslice each values keys exists delete rv2hv
			      sassign aassign preinc i_preinc predec i_predec
			      postinc i_postinc postdec i_postdec trans splice push
			      pop shift unshift andassign orassign warn die anoncode
			      prototype entersub leavesub leavesublv rv2cv
			      method method_named));
	$compartment->permit(qw(concat padany));
	# Keep the args safe
	$_ = undef;
	@_ = ();
	%_ = ();
	my $rc = $compartment->reval("return $text");
	if ($@) {
	    Log(100, "WARNING: Evaluation of expression on line $linenum of $file\n         failed.\nThe failed expression was\n  $text\n");
	    if ($@ =~ /trapped by operation mask (.*)/) {
		Log(100, "An illegal operation ($1) was attempted.\n");
		do_exit(1);
	    } else {
		Log(100, "The error message from the parser was: $@\n");
		do_exit(1);
	    }
	}
	# Try to figure out if $rc is true or false.
	if (!defined($rc) || ($rc eq '') || ($rc =~ /^[-+]?0+(?:\.0+)?$/)) {
	    return 0;
	} else {
	    return 1;
	}
    }
}

sub pp_macro_expand {
    my ($line, $macros, $warn, $quoting, $file, $linenum, $noreplace) = @_;

    if ($quoting) {
        # When quoting is on, if the user quotes a variable name then
        # we need to unquote it or the quoting will be doubled and then
        # there'll be trouble.
        $line =~ s/(['"])((?<![\\\xff])%\{[^%\{\}]+\})\1/$2/g;
    }
    do {
    } while
	$line =~ s/(?<![\\\xff])%\{([^%\{\}]+)\}/
                   my $symbol = $1;
                   # If the symbol is composed of the contents of several other
                   # macros (resolved previously in this loop), and if quoting
                   # is turned on, then the quotes will need to be removed in
                   # order for the lookup to succeed.
                   $symbol =~ s{'}{}g;
		   if (exists($macros->{$symbol})) {
		       # Well, then... try to figure out if it's a number or what
                       if ($macros->{$symbol}+0 != 0 &&
                           $macros->{$symbol} =~ m{^[-+]?(?:\d+|\d+\.\d*|\d*\.\d+|\d+[eEgG][-+]?\d+)$}) {
			   $macros->{$symbol}+0;
		       } elsif ($macros->{$symbol} =~ m{^[-+]?0+(?:\.0+)?$}) {
			   # It's a zero!
			   0;
		       } else {
			   # It's not a number...
			   if ($quoting) {
                               # Don't quote strings that might be references
                               # to other preprocessor macros, unless $noreplace
                               # is on.
                               if ($macros->{$symbol} =~ m{(?<![\\\xff])%\{[^%\{\}]+\}} &&
                                   !$noreplace) {
                                   $macros->{$symbol};
                               } elsif ($macros->{$symbol} =~ m{^["'].*["']$}) {
                                   $macros->{$symbol};
                               } else {
                                   "'".$macros->{$symbol}."'";
                               }
			   } else {
                               $macros->{$symbol};
			   }
		       }
		   } else {
		       Log(100, "ERROR: Undefined preprocessor macro '$symbol' referenced on line $linenum\n       of $file\n") if $warn;
                       if ($noreplace) {
                          "\xff\%{".$1.'}';
                       } elsif ($quoting) {
                          "''";
                       } else {
                          # Return an empty string; this should cause most
                          # expressions to break in such a way that the user
                          # will be alerted to their error. :)
                          '';
                       }
		   }
                            /egs;

    # Undo fixups that we've put in
    $line =~ s/\xff%{/%{/g;
    return $line;
}

sub config_var_expand {
    my ($line, $ref, $warn) = @_;

#    print "config_var_expand([$line], $ref, $warn)\n";
    return $line if ($line eq '' || ref($ref) !~ /^(?:HASH|Spec::Config)/);

    do {
#	print "line: {$line}\n";
    } while
	$line =~ s/(?<!\\)\$\[([^\$\[\]]+)\]/
                   my $var = $1;
#    print "    var: $var\n";
                   my $val = Spec::Config::accessor_backend($ref, 0, $var);
#    print "    val: $val\n";
                   if (defined($val)) {
		       # Well, then... try to figure out if it's a number or what
		       if ($val+0 != 0) {
			   # It's a number...numify it (well, this probably doesn't
			   # matter too much, but if it needs to be a string, it'll
			   # be re-stringified later)
			   $val+0;
		       } elsif ($val =~ m{^[-+]?0+(?:\.0+)?$}) {
			   # It's a zero!
			   0;
		       } else {
			   # It's not a number...
			   $val;
		       }
		   } else {
		       Log(100, "ERROR: Undefined config variable '$var' referenced during variable expansion\n") if $warn;
		       # Return an empty string; this should cause most expressions to
		       # break in such a way that the user will be alerted of their
		       # error. :)
		       '';
		   }
                            /egs;
#    print "return: {$line}\n";
    return $line;
}

sub get_sysinfo {
    my ($me) = @_;
    my @cflines = ();
    my @infolines = ();

    return() if ($::from_runspec);

    if (exists($me->{'sysinfo_program'}) &&
        $me->{'sysinfo_program'} ne '') {
        my $sysinfo = $me->{'sysinfo_program'};
        # As a special case, do substitution for $[top] or ${top}, to make
        # specifying absolute paths easier.
        $sysinfo =~ s/\$\[top\]/$me->top/eg;
        $sysinfo =~ s/\$\{top\}/$me->top/eg;
        Log(0, "Running \"$sysinfo\" to gather system information.\n") unless ($::quiet && $::from_runspec);
        @infolines = ();
        if ($^O eq 'MSWin32' && (my $infoline = qx{$sysinfo})) {
            @infolines = map { $_."\n" } split(/[\r\n]+/, $infoline);
        } elsif ($^O ne 'MSWin32' && open SYSINFO, '-|', split(/\s+/, $sysinfo)) {
            @infolines = <SYSINFO>;
            close(SYSINFO);
        } else {
            Log(0, "\nERROR: Could not run sysinfo_program \"$sysinfo\".\n       The error returned was \"$!\"\n\n");
        }
        if (@infolines) {
            Log(130, "Read ".(@infolines+0)." total lines from the sysinfo program.\n");
            # Only allow notes-type lines and comments
            @infolines = grep { /$::info_re/ || /^\s*\#/ } @infolines;
            Log(130, "Read ".(@infolines+0)." usable lines from the sysinfo program.\n");
            # Try to get the sysinfo program into a bundle.  Assume there are
            # no spaces in the path, and add each word that exists as a file
            # (and whose path doesn't contain '/perl') to the list of files to
            # bundle.
            foreach my $trypath (split(/\s+/, $sysinfo)) {
                next if $trypath =~ m#[/\\](?:spec)?perl[/\\]#;
                push @{$me->{'files_read'}}, $trypath if -e $trypath;
            }
        }
        if (@infolines) {
	    push @cflines, "# The following settings were obtained by running '".$me->{'sysinfo_program'}."'\n";
	    push @cflines, "default:\n";
	    push @cflines, @infolines;
        } else {
	    Log(130, "Read _NO_ lines from the sysinfo program.  Perhaps there was a problem?\n");
        }
    }
    return @cflines;
}

sub max_copies {
    my $me = shift;
    return 1 if !istrue($me->rate);
    return main::max(main::expand_ranges(@{$me->copylist}));
}

# search keys of an array based on a limited wild card (*)
# and returns the list of keys that match/contain the pattern
sub find_keys {
    my ($me, $pat) = @_;
    my @temp;
    if ($pat =~ s/\*$//) { # if pattern ends in "*"
	@temp = sort bytrailingnum grep (m/^$pat[0-9.]*/, list_keys($me));
    } else {
	@temp = ($pat) if exists $me->{$pat};
    }
    return @temp;
}

# Return a list of sets that the benchmarks are in
sub benchmark_in_sets {
    my ($me, @benchmarks) = @_;
    my %sets;
    for my $bench (@benchmarks) {
	for my $set (keys %{$me->{'benchsets'}}) {
	    $sets{$set}++ if exists $me->{'benchsets'}{$set}{'benchmarks'}{$bench};
	}
    }
    return keys %sets;
}

sub bind {
    my $me = shift;

    if ($me->tune eq 'base') {
        # The binding is not allowed to vary on a per-benchmark
        # basis for base runs
        my $config = $me->{'config'};
        $config = $::global_config unless (blessed($config) && $config->isa('Spec::Config'));
        my @sets = $config->benchmark_in_sets($me->benchmark);
        my $rc = $config->default_lookup('bind', $me->{'ext'}, $me->{'mach'}, @sets);
        return $rc;
    } else {
        my $tmp = $me->accessor_nowarn('bind');
        return $tmp;
    }
}

sub parallel_test {
    my $me = shift;

    # No parallel test/train for OMP2012
    return 1 if $::lcsuite =~ /^(omp2012)$/;

    my $rc = $me->accessor_nowarn('parallel_test');
    if (defined($rc) && $rc == 0) {
        # Default, not set on the command line
        $rc = $me->copies;
    } else {
        $rc = 1 unless defined($rc);
    }

    return $rc;
}

sub copies {
    my $me = shift;

    return 1 unless istrue($me->rate);

    if ($me->tune eq 'base') {
        # The number of copies is not allowed to vary on a per-benchmark
        # basis for base runs
        my $config = $me->{'config'};
        my $rc;
        $config = $::global_config unless (blessed($config) && $config->isa('Spec::Config'));
        if (exists($config->{'clcopies'}) && $config->{'clcopies'} ne '') {
            $rc = $config->{'clcopies'};
        } else {
            # The 'accessor_nowarn' is because sometimes copies is invoked
            # on a non-benchmark config object.
            my @sets = $config->benchmark_in_sets($me->accessor_nowarn('benchmark'));
            $rc = $config->default_lookup('copies', $me->{'ext'}, $me->{'mach'}, @sets);
        }
        return main::expand_ranges(split(/,+|\s+/, $rc));
    } else {
        foreach my $check (qw(copies clcopies)) {
            my $tmp = $me->accessor_nowarn($check);
            next unless defined($tmp) && $tmp ne '';
            return main::expand_ranges(split(/,+|\s+/, $tmp));
        }
        return main::expand_ranges(@{$me->copylist});
    }
}

sub ranks {
    my ($me, $tune) = @_;

    my $what = ($::lcsuite eq 'mpi2007') ? 'ranks' : 'threads';

    $tune = $me->tune unless defined($tune) && $tune ne '';
    if ($tune eq 'base') {
        # The number of ranks is not allowed to vary on a per-benchmark
        # basis for base runs
        my $config = $me->{'config'};
        my $rc;
        $config = $::global_config unless (blessed($config) && $config->isa('Spec::Config'));
        if (exists($config->{'clranks'}) && $config->{'clranks'} ne '') {
            $rc = $config->{'clranks'};
        } else {
            my @sets = $config->benchmark_in_sets($me->benchmark);
            $rc = $config->default_lookup($what, $me->{'ext'}, $me->{'mach'}, @sets);
        }
        return $rc;
    } else {
        foreach my $check ($what, 'clranks') {
            my $tmp = $me->accessor_nowarn($check);
            next unless defined($tmp) && $tmp ne '' && $tmp > 0;
            return $tmp;
        }
        return ($::global_config->{$what} > 0) ? $::global_config->{$what} : 1;
    }
}

# Build a tree of references
sub ref_tree {
    my ($ref, $label, $leaves, @rest) = @_;
    my %seen;
    my @rc;
    return () unless ref($leaves) eq 'ARRAY';

    for my $leaf (@{$leaves}) {
	next unless defined($leaf);
	next if $seen{$leaf}++;
	$ref->{$leaf} = { } if ref($ref->{$leaf}) ne 'HASH';
	$refmapping{qq/$ref->{$leaf}/} = "$label:$leaf" if (!exists $refmapping{qq/$ref->{$leaf}/});
#print "ref_tree($ref, $label:$leaf, $leaves, [".join(',', @rest)."]) = ".$ref->{$leaf}."\n";
	push (@rc, $ref->{$leaf});
	push (@rc, ref_tree($ref->{$leaf}, "$label:$leaf", @rest)) if @rest > 0;
    }
    return @rc;
}

sub unshift_ref {
    my ($me, @refs) = @_;
    unshift (@{$me->{'refs'}}, @refs);
}
sub shift_ref {
    my ($me) = @_;
    my $out = shift @{$me->{'refs'}};
    return $out;
}
sub push_ref {
    my ($me, @refs) = @_;
    push (@{$me->{'refs'}}, @refs);
}
sub pop_ref {
    my ($me) = @_;
    my $out = pop @{$me->{'refs'}};
    return $out;
}

1;
