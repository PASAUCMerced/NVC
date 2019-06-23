#
# parse.pl
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: parse.pl 1856 2012-09-25 20:35:11Z CloyceS $

use strict;
use Scalar::Util qw(reftype);

use Getopt::Long;
use Text::ParseWords;
require 'flagutils.pl';
require 'util.pl';

my $version = '$LastChangedRevision: 1856 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'parse.pl'} = $version;

sub parse_commandline {
    my ($config, $cl_opts) = @_;
    my @macros = ();
    my @undefkeys = ();
    my @flagsurls = ();
    my $bp_bench = undef;

    # No defaults
    $cl_opts->{'bundlename'} = $cl_opts->{'bundleaction'} = '';

    if (exists $ENV{'SPEC_RUNSPEC'}) {
	unshift @ARGV, shellwords($ENV{'SPEC_RUNSPEC'});
    }

    Getopt::Long::config("no_ignore_case");
    my @actions = ();
    my $rc = GetOptions ($cl_opts, qw(
			config|c=s
			make_no_clobber|make-no-clobber|M
			ext|extension|e=s
			help|h|?
			mach|machine|m=s
			iterations|n=s
			output_format|output-format|o=s
			speed
			rate|hrate|homogenousrate|rateclassic|r:i
			shrate|staggeredhomogenousrate:i
                        stagger=i
			size|input|i=s
			tune|tuning|T=s
			clcopies|copies|C=s
			max_active_compares|max-active-compares|maxcompares=i
			username|U=s
			rebuild|D
			nobuild|N
			deletework|d
			unbuffer|f
			ignore_errors|ignoreerror|ignore-errors|I!
			verbose|debug|v=i
			version|V
			setprocgroup!
			reportable!
			strict!
			s
                        loose|l
                        fake|dryrun|dry-run|dry_run!
                        table!
			rawformat|R
                        test:s
                        comment=s
			delay=i
			feedback!
                        reportonly|fakereport
                        update-flags|update_flags|flagupdate|flagsupdate|newflags|getflags|update
                        notes_wrap_columns|notes-wrap|notes-wrap-columns|noteswrap=i
                        info_wrap_columns|info-wrap|info-wrap-columns|infowrap=i
                        graph_min|graph-min|graphmin=f
                        graph_max|graph-max|graphmax=f
                        graph_auto|graph-auto!
                        http_proxy|http-proxy=s
                        http_timeout|http-timeout=i
                        review!
                        mockup|fakereportable
                        check_version|check-version
                        train_with=s
                        ranks|threads=i
                        parallel_setup|parallel-setup=i
                        parallel_setup_type|parallel-setup-type=s
                        parallel_setup_prefork|parallel-setup-prefork=s
                        copynum=i
                        parallel_test|parallel-test=i
		        parallel_test_workloads|parallel-test-workloads=s
                        use_submit_for_speed|use-submit-for-speed!
                        from_runspec:i
                        logfile=s
                        lognum=s
                        log_timestamp|log-timestamp!
                        userundir=s
                        preenv!
                        note_preenv|note-preenv
                        keeptmp!
                        power!
                        platform=s
                        device=s
			),
			 'define|S=s' => \@macros,
			 'undef=s' => \@undefkeys,
			 'action|a=s' => \@actions,
                         'make-bundle|make_bundle=s' => sub { if ($_[1]) { $cl_opts->{'bundlename'} = $_[1]; $cl_opts->{'bundleaction'} = 'make'; } else { delete $cl_opts->{'bundlename'}; delete $cl_opts->{'bundleaction'}; } },
                         'unpack-bundle|unpack_bundle=s' => sub { if ($_[1]) { $cl_opts->{'bundlename'} = $_[1]; $cl_opts->{'bundleaction'} = 'unpack'; } else { delete $cl_opts->{'bundlename'}; delete $cl_opts->{'bundleaction'}; } },
                         'use-bundle|use_bundle=s' => sub { if ($_[1] && $::from_runspec == 0) { $cl_opts->{'bundlename'} = $_[1]; $cl_opts->{'bundleaction'} = 'use'; } else { delete $cl_opts->{'bundlename'}; delete $cl_opts->{'bundleaction'}; } },
                         'configpp' => sub { if ($_[1]) { push @actions, 'configpp' } else { @actions = grep { !/configpp/ } @actions } },
			 'basepeak:s@' => sub { if (!defined($_[1]) || $_[1] eq '') { $bp_bench = 'full'; } else { push @$bp_bench, $_[1]; } },
			 'flagsurl|flags|F=s' => \@flagsurls,
			 );

    # Just in case there has been an oversight and a nonvolatile option has
    # been inserted into the list of command line options, throw it out and
    # issue a warning.
    foreach my $nvconfig (keys %$main::nonvolatile_config) {
	if (exists($cl_opts->{$nvconfig})) {
	    delete $cl_opts->{$nvconfig};
	    Log(0, "$nvconfig is immutable.  Do not attempt to set it via the command line.\n");
	}
    }

    if ($::from_runspec && $cl_opts->{'userundir'} ne '') {
        $cl_opts->{'rundir'} = $cl_opts->{'userundir'};
    }

    # Set timestamp logging
    $config->{'log_timestamp'} = $cl_opts->{'log_timestamp'} if exists($cl_opts->{'log_timestamp'});

    # Check settings for ext and mach
    foreach my $what (qw(ext mach)) {
      next unless exists($cl_opts->{$what});
      if ($cl_opts->{$what} !~ /^[A-Za-z0-9_., -]+$/) {
        Log(100, "ERROR: Illegal characters in '$what'; please use only alphanumerics,\n");
        Log(100, "       underscores (_), hyphens (-), and periods (.).\n");
        $rc = 1;
      }
    }

    # Check bundle name 
    if (   exists($cl_opts->{'bundlename'})
        && $cl_opts->{'bundlename'} ne '') {
      my $tmpname = basename($cl_opts->{'bundlename'});
      if ($tmpname !~ /^[A-Za-z0-9_.-]+$/) {
        Log(100, "ERROR: Illegal characters in bundle name; please use only alphanumerics,\n");
        Log(100, "       underscores (_), hyphens (-), and periods (.).\n");
        $rc = 1;
      }
    }

    # Expand the list of benchmarks for basepeak
    if (ref($bp_bench) eq 'ARRAY') {
	$bp_bench = [ split(/[,:]+/, join(',', @$bp_bench)) ];
	# Now throw back everything that is an existing filename
	$config->{'bp_bench'} = [ ];
	foreach my $bench (@$bp_bench) {
	    if (-e $bench) {
		# It's a file, so put it back in @ARGV to be processed
		unshift @ARGV, $bench;
	    } else {
		push @{$config->{'bp_bench'}}, $bench;
	    }
	}
	$config->{'bp_bench'} = 'full' unless @{$config->{'bp_bench'}};
    } elsif (defined($bp_bench) && $bp_bench eq 'full') {
	$config->{'bp_bench'} = 'full';
    }

    # Immediately set verbose if asked; there's a lot of stuff that happens
    # between now and finalize_config
    $config->{'verbose'} = $cl_opts->{'verbose'} if exists($cl_opts->{'verbose'});

    # Save the value for ranks, if one was provided
    $cl_opts->{'clranks'} = $cl_opts->{'ranks'} if exists $cl_opts->{'ranks'};

    # Set the training workload (if any)
    $config->{'train_with'} = $cl_opts->{'train_with'} if exists($cl_opts->{'train_with'});

    # Fix up macros for use when parsing the config file
    foreach my $macro (@macros) {
        if ($macro =~ /^([^=:]+)[=:](.*)$/o) {
            # It's a name/value pair
            $cl_opts->{'pp_macros'}->{$1} = $2;
        } else {
            # It's just a name; define it to 1
            $cl_opts->{'pp_macros'}->{$macro} = 1;
        }
    }
    foreach my $key (@undefkeys) {
	$cl_opts->{'pp_unmacros'}->{$key} = 1;
	delete $cl_opts->{'pp_macros'}->{$key} if exists $cl_opts->{'pp_macros'}->{$key};
    }

    # --fakereportable and --mockup just mean '--fakereport --reportable',
    # so fix things up.
    if (exists $cl_opts->{'mockup'}) {
       $cl_opts->{'reportonly'} = 1;
       $cl_opts->{'reportable'} = 1;
       delete $cl_opts->{'fakereportable'};
       delete $cl_opts->{'mockup'};
    }

    # --reportonly and --fakereport are just handy synonyms for
    # '--action=report', so act accordingly
    if (exists $cl_opts->{'reportonly'}) {
	@actions = ('report');
	delete $cl_opts->{'reportonly'};
    }

    # Check the action(s) specified.  This will help catch typos like
    # '-a <cfgfile>'.  In any case, only the last one specified gets stuffed
    # into the action slot.
    foreach my $action (map { lc($_) } @actions) {
	if (! grep { $action eq $_ } @{$::nonvolatile_config->{'valid_actions'}}) {
	    die "\n\"$action\" is not a valid action!\n\n";
	}
    }
    my $action = pop @actions;
    $cl_opts->{'action'} = $action if (defined($action) && $action);

    # 'loose', 'strict', and 'reportable' are all really ways of talking
    # about 'reportable', so munge things up properly
    # We don't do a whole lot of checking here because those would only
    # cover strange cases where the user says '--strict --noreportable'
    # or things like that, and our job isn't to help people be not stupid
    if (exists $cl_opts->{'loose'}) {
	$cl_opts->{'reportable'} = 1 - $cl_opts->{'loose'};
	delete $cl_opts->{'loose'};
    }
    for my $strictopt (qw(strict s)) {
	if (exists $cl_opts->{$strictopt}) {
	    $cl_opts->{'reportable'} = $cl_opts->{$strictopt};
	    delete $cl_opts->{$strictopt};
	}
    }

    # Run the Perl test suite, if asked
    if (exists $cl_opts->{'test'} && defined($cl_opts->{'test'})) {
      print "Running the Perl test suite...\n";
      chdir main::jp($ENV{'SPEC'}, 'bin');
      my @args = ( main::jp($ENV{'SPEC'}, 'bin', 'specperl'), main::jp('test', 'TEST') );
      push @args, '-dots' if $cl_opts->{'test'} eq 'dots';
      if ($^O =~ /MSWin/) {
          # If we use exec for Windows, the user gets dumped to the command
	  # line long before the tests are finished.
	  system @args;
	  exit $?;
      } else {
	  exec @args;
	  # This should never happen
	  die "exec of $args[0] failed: $!\n";
      }
    }

    # Take care of the flags file(s)
    @flagsurls = split(/,+/, join(',', @flagsurls));
    $cl_opts->{'flagsurl'} = [];
    if (@flagsurls && !grep { /^noflags$/ } @flagsurls) {
        foreach my $url (@flagsurls) {
            $url =~ s|\\|/|g; # Change \ to / for Windows users
            if ($url !~ m|^[^:]+://|) {
                if (! -e $url) {
                    Log(0, "ERROR: Specified flags file ($url) could not be found.\n");
                    Log(0, "       To get a flags report, you must re-format generated results with a\n");
                    Log(0, "       valid flags file.\n");
                    next;
                }
            } elsif ($url !~ /^(http|ftp|file):/) {
                die "ERROR: Unsupported flags file URL scheme in \"$url\";\n       please use file:, http:, or ftp:.\nStopped";
            }
            push @{$cl_opts->{'flagsurl'}}, $url;
        }
    }
    if (@{$cl_opts->{'flagsurl'}} == 0) {
        # No flags files found
        delete $cl_opts->{'flagsurl'};
    }

    # Staggered homogenous rate => regular rate
    # Since this can now specify the number of copies as well, treat it
    # carefully...
    if (exists($cl_opts->{'shrate'})) {
        $cl_opts->{'rate'} = 1;
        if (($cl_opts->{'shrate'} >= 400 && $cl_opts->{'shrate'} < 500) ||
            $cl_opts->{'shrate'} == 998 || $cl_opts->{'shrate'} == 999) {
            Log(0, "\nWARNING: You have specified a number of copies that looks like a benchmark\n");
            Log(0, "         selection.  If this is really the correct number of copies to run,\n");
            Log(0, "         specify it using the '--copies' command line flag.\n\n");
            unshift @ARGV, $cl_opts->{'shrate'};
        } elsif ($cl_opts->{'clcopies'} eq '') {
            $cl_opts->{'clcopies'} = $cl_opts->{'shrate'};
        }
        $cl_opts->{'shrate'} = 1;
    } elsif (exists($cl_opts->{'rate'})) {
        if (($cl_opts->{'rate'} >= 400 && $cl_opts->{'rate'} < 500) ||
            $cl_opts->{'rate'} == 998 || $cl_opts->{'rate'} == 999) {
            Log(0, "\nWARNING: You have specified a number of copies that looks like a benchmark\n");
            Log(0, "         selection.  If this is really the correct number of copies to run,\n");
            Log(0, "         specify it using the '--copies' command line flag.\n\n");
            unshift @ARGV, $cl_opts->{'rate'};
        } elsif ($cl_opts->{'clcopies'} eq '') {
            $cl_opts->{'clcopies'} = $cl_opts->{'rate'};
        }
	$cl_opts->{'rate'} = 1;
    }

    # Set the username _now_ so that immediate substitution in the config file
    # will get the "right" value.
    $config->{'username'} = $cl_opts->{'username'} if exists($cl_opts->{'username'});

    # Unset the http proxy?
    if ($cl_opts->{'http_proxy'} eq 'none') {
      delete $ENV{'http_proxy'};
      $cl_opts->{'http_proxy'} = '';
    }

    # Options to pass to rawformat
    $config->{'rawformat_opts'} = [];
    foreach my $opt (qw( table review graph_auto )) {
        push @{$config->{'rawformat_opts'}}, ($cl_opts->{$opt} ? "--$opt" : "--no$opt") if exists($cl_opts->{$opt});
    }
    foreach my $opt (qw( graph_min graph_max verbose )) {
        push @{$config->{'rawformat_opts'}}, ("--$opt", $cl_opts->{$opt}) if exists($cl_opts->{$opt});
    }

    # Make sure that parallel_setup_type is set properly
    if (exists($cl_opts->{'parallel_setup_type'}) && $cl_opts->{'parallel_setup_type'} !~ /^(fork|submit|none)$/i) {
        Log(100, "ERROR: Parallel setup type specified is incorrect; it must be one of 'fork',\n        'submit', or 'none'.\n");
        $rc = 1;
    }

    # If doing rate and parallel_test is not specified, then default it to
    # number of copies
    if ($cl_opts->{'rate'} && !exists($cl_opts->{'parallel_test'})
        && $cl_opts->{'clcopies'} > 0) {
        $cl_opts->{'parallel_test'} = $cl_opts->{'clcopies'};
    }
    if (exists($cl_opts->{'parallel_test'}) && $cl_opts->{'parallel_test'} < 1) {
        Log(100, "ERROR: Setting for parallel_test must be a positive integer\n");
        delete $cl_opts->{'parallel_test'};
    }

    # OMP2012 shouldn't be using --rate, but it probably won't hurt to be safe
    if ($::lcsuite =~ /^(omp2012)$/) {
        delete $cl_opts->{'parallel_test'};
        delete $cl_opts->{'parallel_setup'};
    }

    # runspec is the only one allowed to set its own logfile and lognum
    if (!$cl_opts->{'from_runspec'} &&
        (exists($cl_opts->{'logfile'}) || exists($cl_opts->{'lognum'}))) {
        Log(0, "ERROR: Only runspec itself may use --logfile or --lognum\n");
        delete $cl_opts->{'logfile'};
        delete $cl_opts->{'lognum'};
    }
    $::from_runspec = $cl_opts->{'from_runspec'} if $cl_opts->{'from_runspec'};

    if (!$rc || istrue($cl_opts->{'help'})) {
	print "For help, type \"runspec --help\"\n";
        #usage();
	exit (!$rc ? 1 : 0);
    }

    return 1;
}

sub validate_options {
    my ($config) = @_;

    if (istrue($config->unbuffer)) {
	$|=1;
    }
    if ($config->ext eq '') {
	Log(0, "\nERROR: Please specify an extension!  (-e or ext= in config file)\n");
	do_exit(1);
    }

    # Check the types for numerics
    my ($rc, $badval);
    if (istrue($config->rate)) {
        ($rc, $badval) = check_numbers($config->copylist);
        if (!$rc) {
            Log(100, "\nERROR: '$badval' is not a valid value for copies!\n");
            do_exit(1);
        }
    }
    ($rc, $badval) = check_numbers($config->iterlist);
    if (!$rc) {
        Log(100, "\nERROR: '$badval' is not a valid value for iterations!\n");
        do_exit(1);
    }
    ($rc, $badval) = check_numbers($config->max_active_compares);
    if (!$rc) {
        Log(100, "\nERROR: '$badval' is not a valid value for max_active_compares!\n");
        do_exit(1);
    }
    ($rc, $badval) = check_numbers($config->verbose);
    if (!$rc) {
        Log(100, "\nERROR: '$badval' is not a valid value for verbose!\n");
        do_exit(1);
    }

    if ($::lcsuite eq 'accelv1') {
        # Check platform and device
        my $ok = 1;
        foreach my $thing (qw(platform device)) {
            my $val = $config->accessor_nowarn($thing);
            if (defined($val) && $val =~ /^\s*$/) {
                Log(100, "\nERROR: Please specify a value for $thing (--$thing or $thing= in config file)\n");
                $ok = 0;
            }
        }
        do_exit(1) unless $ok;
    }

    if (istrue($config->fake) && !istrue($config->teeout)) {
      $config->{'teeout'} = 1;
    }
}

sub check_numbers {
    my ($aref) = @_;
    my ($rc, $badval);

    if (ref($aref) eq 'ARRAY') {
	foreach my $thing (@{$aref}) {
	    $rc = check_number($thing);
	    return ($rc, $thing) unless $rc;
	}
    } elsif (ref($aref) eq '') {
	$rc = check_number($aref);
	return ($rc, $aref) unless $rc;
    } else {
	Log(100, "Can't check object of type ".ref($aref)."!\n");
	return (1, $aref);
    }
    return(1, undef);
}

sub check_number {
    my ($thing) = @_;

    return scalar($thing =~ /^\d+$/o);
}
	
sub resolve_choices {
    my ($config, $cl_opts) = @_;

    # List of formats to do; rawformat will sort it all out
    $config->{'formatlist'} = [ split(/[:,]+/, $config->output_format) ];

    my $action = $config->action;
    my $tmp = choose_string($action, @{$config->valid_actions});
    if (!defined $tmp) {
        if (istrue($cl_opts->{'check_version'})) {
          return 0;
        } else {
          Log(0, "I don't know what type of action '$action' is!\n");
          do_exit(1);
        }
    }
    # Fix up the small number of synonyms that we have
    if (lc($action) eq 'onlyrun') {
      $action = 'only_run';
    } elsif (lc($action) eq 'run') {
      $action = 'validate';
    } elsif (lc($action) eq 'runsetup') {
      $action = 'setup';
    }
    $config->action($action);

    $config->{'tunelist'} = [ choose_strings('Tune', $config->{'tune'}, 
                                             [ @{$config->valid_tunes} ], []) ];

    # Take care of size 'all':
    if ($config->{'size'} =~ /\ball\b/) {
	if ($::lcsuite =~ /cpu(?:2006|v6)/) {
	  $config->{'size'} =~ s/\ball\b/test,train,ref/;
	} elsif ($::lcsuite =~ /^(mpi2007|omp2001|omp2012)$/) {
	  ::Log(0, "\nERROR: 'all' is not a valid workload size for $::suite\n\n");
	  ::do_exit(1);
	} elsif ($::lcsuite eq 'omp2012') {
	  ::Log(0, "\nERROR: 'all' is not a valid workload size for OMP2012\n\n");
	  ::do_exit(1);
	} else {
	  # It doesn't mean anything special... what did you expect?
	}
    }

    $config->{'iterlist'} = [ split(/[,:[:space:]]+/, $config->{'iterations'}) ];
    $config->{'extlist'}  = [ split(/[,:[:space:]]+/, $config->{'ext'}) ];
    $config->{'machlist'} = [ split(/[,:[:space:]]+/, $config->{'mach'}) ];
    $config->{'copylist'} = [ 1 ];  # Placeholder

    my $copies = $config->{'copies'};
    if (exists($config->{'clcopies'}) &&
        $config->{'clcopies'} ne '' && $config->{'clcopies'} != 0) {
        $copies = $config->{'clcopies'};
    } else {
        delete $config->{'clcopies'};
    }
    $config->{'copylist'} = [ split(/[,:]+|\s+/, $copies) ];

# Make sure there is at least one entry in each of the categories
    for (qw(extlist machlist)) {
        $config->{$_} = [ 'default' ] if (ref($config->{$_}) ne 'ARRAY' || @{$config->{$_}} == 0);
    }
    if (ref($config->{'tunelist'}) ne 'ARRAY' ||
        @{$config->{'tunelist'}} == 0) {
        if (istrue($cl_opts->{'check_version'})) {
          return 0;
        } else {
          Log(0, "A valid tuning level must be selected using -T or --tune on the command line\n");
          Log(0, "or by setting 'tunelist' in the configuration file.\n");
          do_exit(1);
        }
    }

    # Fix up the size list if no size was explicitly specified either on the
    # command line or in the config file.
    if (!exists($cl_opts->{'size'}) && $cl_opts->{'size'} eq ''
        && $config->{'size'} eq $::nonvolatile_config->{'default_size'}) {
        my %sizes = ();
        # XXX At this point, benchset_list is unset!
        # XXX It gets set in resolve_user_selection(), but that requires that
        # XXX sizelist already be set. :/
        # I'm just leaving it in for now because I'm terrified of unintended
        # consequences.
        foreach my $bset (@{$config->{'benchset_list'}}) {
            $sizes{$config->{'benchsets'}->{$bset}->{'ref'}} = 1;
        }
        $config->{'size'} = join(',', sort keys %sizes) if @{$config->{'benchset_list'}};
    }

    # Validate the sizes
    $config->{'sizelist'} = [ ];
    if ($::lcsuite =~ /cpu(?:2006|v6)/) {
      foreach my $maybe_size (split(/[,:]+|\s+/, $config->{'size'})) {
        if ($maybe_size =~ /^(?:all|test|train|ref)$/i) {
          push @{$config->{'sizelist'}}, $maybe_size;
        } else {
          Log(0, "Notice: '$maybe_size' is not a valid workload size.  It will be added to the list\n");
          Log(0, "         of benchmarks to run.\n");
          push @ARGV, $maybe_size;
        }
      }
    } else {
      # Just take the sizes as specified.
      $config->{'sizelist'} = [ split(/[,:]+|\s+/, $config->{'size'}) ];
    }
    if (@{$config->{'sizelist'}} == 0) {
      Log(0, "\nNo workload size specified!\n");
      do_exit(1);
    }

    my @candidates = (@ARGV);
    if (@candidates+0 < 1 && exists $config->{'runlist'}) {
        push @candidates, split(/(?:\s+|\s*[,:]+\s*)/, $config->{'runlist'});
    }
    my ($benchsets, $benchmarks, $add_files) = resolve_user_selection($config, \@candidates);
    $config->{'benchset_list'} = $benchsets;
    if (!@{$benchmarks}) {
        if (istrue($cl_opts->{'check_version'})) {
          return 0;
        } else {
          Log(0, "\nNo benchmarks specified!\n");
          do_exit(1);
        }
    }
    $config->{'runlist'} = $benchmarks;
    $config->{'bundle_files'} = $add_files;

    my $ok = 1;
    # Barf if multiple benchsets with incompatible workloads are chosen.
    my @benchsets = @{$config->{'benchset_list'}};
    my $first_set = shift(@benchsets);
    foreach my $bset (@benchsets) {
        for my $size_class (qw(test train ref)) {
            my $first_size = $config->{'benchsets'}->{$first_set}->{$size_class};
            if ($first_size ne $config->{'benchsets'}->{$bset}->{$size_class}) {
                Log(0, "ERROR: Benchsets $first_set and $bset cannot be run together; $size_class workload\n");
                Log(0, "       sizes do not match ($first_size vs $config->{'benchsets'}->{$bset}->{$size_class})\n");
                $ok = 0;
            }
        }
    }
    do_exit(1) if $ok != 1;

    return 1;
}

sub resolve_user_selection {	## figure out which benchmarks are to be run
                                ## and return them as a list.
    my ($config, $selection) = @_;       ## typically, what is on the command line
    my @benchmarks = ();
    my @benchsets = ();
    my @add_files = ();
    my %benchmark_seen;
    my $sel;
    my $set;
    my $files_ok = $config->{'bundleaction'} eq 'make';

    @$selection = ::expand_all(@$selection);
    my %leftovers = ();
    foreach my $bset (sort keys %{$config->{'benchsets'}}) {
        $leftovers{$bset} = { map { $_ => 1 } keys %{$config->{'benchsets'}->{$bset}->{'benchmarks'}} };
    }

    # Find out what benchmarks the user wants to run, knock out duplicates
    my $error = 0;
    for my $sel (@$selection) {
	my @temp = ();
	my $not = 0;
	if ($sel =~ m/^\^+(.*)/) { ## if the argument begins with a ^
	    $sel = $1;            ## it implies a NOT of the selection
	    if ($config->action =~ /(?:validate|report)/ &&
                istrue($config->reportable)) {
		Log(0, "Benchmark exclusion is not allowed for a reportable run; ignoring\n");
	    } else {
		$not = 1;
	    }
	}

	# look for the selection in the list of benchmark sets
	if (exists $config->{'benchsets'}{$sel}) {
	    push @benchsets, $sel;
	    my $ref = $config->{'benchsets'}{$sel}{'benchmarks'};
	    push @temp, map { $ref->{$_} } keys %$ref;
	} else {
            my $temp = find_benchmark($config, $sel);
            if (!defined $temp) {
                if ($files_ok) {
	            # Windows users mustn't use wildcards -- the shell doesn't
		    # expand them, and the Win32 module expands them
		    # incompletely.
		    if (   $^O =~ /MSWin/
                        && ($sel =~ /\?/ || $sel =~ m#(?<![/\\])\*#)) {
			Log(0, "\nERROR: Specification of files with wildcards is not supported on Windows.\n");
			do_exit(1);
		    }
                    my @add = check_file($config, $sel);
                    $files_ok = 2 unless @add;
                    push @add_files, @add;
                    next;
                } else {
                    Log(0, "Can't find benchmark '$sel'\n");
                }
            } else {
                @temp = ($temp);
            }
	} 

	if (!@temp && ($files_ok == 0 || @add_files == 0)) {
	    Log(0, "Can't parse '$sel' into a benchmark name\n");
	    next;
	}

        ## process the temporary list of benchmarks
	for my $bench (sort { $a->benchmark cmp $b->benchmark } @temp) {
	    my $name = $bench->benchmark;
	    if ($not) { ## delete this benchmark from the list
		## don't bother removing it if we haven't added it yet
		next if !$benchmark_seen{$name};
		Log(4, "  '$name' removed\n");
		$benchmark_seen{$name} = 0;
		## remove (filter) it from the benchmarks list
		@benchmarks = grep { $name ne $_->benchmark } @benchmarks;
	    } else { ## add it to the benchmark list
		next if $benchmark_seen{$name}; ## skip if we have seen it
		push (@benchmarks, $bench); ## add it to the final list
		$benchmark_seen{$name} = 1; ## flag that we have seen this
		Log(24, "  '$name' added\n");
	    }
	}
    }

    # If a benchset was requested by name, and the workload size isn't set or
    # hasn't been changed from the default, treat the default as the requested
    # size class and get the size from the benchsets requested.  This won't
    # break CPU (where ref==ref), and will work for MPI2007.
    my @sizelist = @{$config->{'sizelist'}};
    if (@benchsets || @benchmarks) {
        if (    @sizelist == 0
            || (@sizelist == 1 && $sizelist[0] eq $::nonvolatile_config->{'default_size'})) {

            my @tmp_benchsets = @benchsets;
            if (@tmp_benchsets == 0) {
                # This can happen if a single benchmark or list of benchmarks has
                # been requested
                @tmp_benchsets = $config->benchmark_in_sets($benchmarks[0]->benchmark);
            }

            # We'll just pick the size from the first benchset that has a
            # matching class.  (If it's not the first one, there's trouble.)
            # If there's still a mismatch, then the tools are right to complain
            my $class = $sizelist[0];
            $config->{'size'} = undef;
            for(my $i = 0; $i < @tmp_benchsets && !defined($config->{'size'}); $i++) {
                $config->{'size'} = $config->{'benchsets'}->{$tmp_benchsets[$i]}->{$class};
            }
            $config->{'sizelist'} = [ $config->{'size'} ] if defined($config->{'size'});
        }
    }

    # Now that the list of benchmarks is generated, if reportable is set,
    # check to see if it makes up at least one whole benchset.  If not,
    # complain.
    if ($config->action =~ /(?:validate|report)/ &&
        istrue($config->reportable)) { 
        foreach my $bench (@benchmarks) {
            foreach my $bset (sort keys %leftovers) {
                delete $leftovers{$bset}->{$bench->benchmark};
            }
        }
        foreach my $bset (sort keys %leftovers) {
            if ((keys %{$leftovers{$bset}}) == 0) {
                # All benchmarks in this bset were found!
                # But ignore it anyway if one of its workloads doesn't agree
                # with what's been chosen.
                if (    (grep { /^\Q$bset\E$/ } @benchsets) == 0
                    && supports_workloads($config->{'benchsets'}->{$bset}, $config->{'sizelist'})) {
                    push @benchsets, $bset unless grep { /^\Q$bset\E$/ } @benchsets;
                }
            }
        }

        if (@benchsets == 0) {
            if (@benchmarks == 0) {
                Log(0, "\nNo benchmark suite selected!");
                my @choices = ::expand_all('all');
                if ($choices[0] eq 'all') {
                    # Don't know the set of valid benchsets for this benchmark
                    @choices = ();
                } elsif (@choices > 1) {
                    Log(0, "  Expected one or more of '".join("', '", @choices)."' or 'all'.");
                } else {
                    Log(0, "  Expected '".join("', '", @choices)."' or 'all'.");
                }
                Log(0,"\n");
            } else {
                Log(0, "\nIndividual benchmark selection is not allowed for a reportable run\n");
            }
            do_exit(1);
        }
    }

    if ($files_ok == 2) {
        # There was a file/dir not found while attempting to make a bundle
        Log(0, "\nNot all extra files specified for bundling were found; aborting\n");
        do_exit(1);
    }

    return (\@benchsets, \@benchmarks, \@add_files);
}

sub supports_workloads {
    my ($bset, $sizes) = @_;
    
    my $ok = 1;
    for(my $i = 0; $i < @$sizes; $i++) {
        my $size = $sizes->[$i];
        if ($size =~ /^(?:ref|test|train)$/) {
            # A size class -- make sure that the benchset has one defined
            if (exists($bset->{$size})) {
                # Now make sure that in future we refer to the size and not the
                # class, since in the end everything needs to be concrete.
                $sizes->[$i] = $bset->{$size};
            } else {
                $ok = 0; # No class == no workload == not supported
            }
        } else {
            my $size_ok = 0;
            foreach my $class (qw(test train ref)) {
                $size_ok = 1 if ($size eq $bset->{$class});
            }
            $ok = 0 unless $size_ok;
        }
    }

    return $ok;
}

sub check_file {
    my ($config, $file) = @_;
    my $top = $config->top;

    if ($^O =~ /MSWin/) {
        $top = Win32::GetLongPathName($top);
        $file = Win32::GetLongPathName($file);
	$file =~ s#[\\/]\.$##;   # If it refers to a directory, let that be it.
    }

    # Prepend $top to relative filenames
    my $path = $file;
    $path = jp($top, $file) unless $path =~ m#^(?:/|(?:[A-Z]:)?\\)#;

    # Strip $top from filenames so that they'll look nice later
    $file =~ s#^\Q$top\E[/\\]##;
        
    # Disallow inclusion of top-level dirs that could either
    # a) wreck the recipient's installation
    # b) make the bundle file huge and maybe a)
    my $check_re = '';
    $check_re = 'i' if ($^O =~ /MSWin/);
    $check_re = qr#^(?${check_re}:(?:\Q$top\E[/\\])?(?:benchspec(?:[/\\]$::suite)?|bin(?:[/\\](?:lib|formats|formatter))?|result|config|Docs|Docs\.txt|redistributable_sources|tmp|tools|install_archives))#;
    if ($file =~ /$check_re/) {
        Log(0, "ERROR: Top-level $::suite directories and files under them may not be included\n");
        Log(0, "       in a bundle.  Ignoring \"$file\"\n");
        return ();
    }
    $check_re = '';
    $check_re = 'i' if ($^O =~ /MSWin/);
    $check_re = qr#^(?${check_re}:(?:\Q$top\E[/\\])?(?:Revisions|install\.bat|install\.sh|shrc|shrc\.bat|MANIFEST|README(?:\.txt)?|LICENSE(?:\.txt)|SUMS\.tools|cshrc|version\.txt|uninstall.sh))$#;
    if ($file =~ /$check_re/) {
        Log(0, "ERROR: Top-level $::suite files may not be overwritten by bundled files.\n       Ignoring \"$file\"\n");
        return ();
    }

    if (-d $path) {
        Log(24, "Adding files under directory \"$file\" to bundle list\n");
	# Completely expand the list of files, excluding all the directories.
	# This is so the MD5-generation code in make_bundle() doesn't have to
	# do it.
	return ::list_all_files($path);
    } elsif (-f $path) {
        Log(24, "Adding file \"$file\" to bundle list\n");
    } else {
        Log(0, "ERROR: \"$file\" is neither a file nor a directory\n");
        return();
    }

    return $file;
}

1;
