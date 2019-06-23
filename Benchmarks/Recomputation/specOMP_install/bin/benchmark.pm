#
# benchmark.pm
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: benchmark.pm 1899 2012-10-15 00:14:02Z CloyceS $
#

package Spec::Benchmark;
use strict;
use File::Path;
use File::Basename;
use File::stat;
use IO::File;
use IO::Dir;
use Cwd;
use IO::Scalar;
use IO::Uncompress::Bunzip2 qw(:all);
use Digest::MD5;
use Carp;
use MIME::Base64;
use Scalar::Util qw(reftype);
use Math::BigFloat;
use Time::HiRes;
use POSIX qw(:sys_wait_h);
use String::ShellQuote;
use vars '@ISA';

@ISA = (qw(Spec::Config));

my $version = '$LastChangedRevision: 1899 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'benchmark.pm'} = $version;

# List of things that MUST be included in the MD5 hash of options.
# This list does not include things which will appear on the compile/link
# command line:
my %option_md5_include = (
                           'srcalt' => '',
                           'RM_SOURCES' => '',
                           'explicit_dimensions' => 0,
                           'strict_rundir_verify' => 0,
                           'version' => 0,
                         );

sub new {
    no strict 'refs';
    my ($class, $topdir, $config, $num, $name) = @_;
    my $me       = bless {}, $class;

    $me->{'name'}        = ${"${class}::benchname"};
    $me->{'num'}         = ${"${class}::benchnum"};
    if ($me->{'name'} eq '' || $me->{'num'} eq '') {
        Log(0, "Either \$benchname or \$benchnum are empty for $name.$num; Ignoring.\n");
        return undef;
    }
    if (!defined(${"${class}::need_math"}) ||
        (${"${class}::need_math"} eq '0') ||
        (lc(${"${class}::need_math"}) eq 'no')) {
        $me->{'need_math'} = '';
    } else {
	$me->{'need_math'} = ${"${class}::need_math"};
    }
    if (${"${class}::sources"} ne '') {
	$me->{'sources'} = ${"${class}::sources"};
    } elsif (@{"${class}::sources"} > 0) {
	$me->{'sources'} = [ @{"${class}::sources"} ];
    } else {
	$me->{'sources'} = { %{"${class}::sources"} };
    }
    $me->{'deps'}        = { %{"${class}::deps"} };
    $me->{'srcdeps'}     = { %{"${class}::srcdeps"} };
    $me->{'workload_dirs'} = { %{"${class}::workloads"} };

    if ($me->{'name'} ne  $name || $me->{'num'} != $num) {
	Log(0, "Benchmark name (".$me->{'num'}.".".$me->{'name'}.") does not match directory name '$topdir'.  Ignoring benchmark\n");
	return undef;
    }

    # Here are the settings that get passed to specdiff.  If these are changed,
    # don't forget to add a new sub for each new item below.
    $me->{'abstol'}      = ${"${class}::abstol"};
    $me->{'reltol'}      = ${"${class}::reltol"};
    # Check the tolerances
    if (! ::istrue(${"${class}::these_tolerances_are_as_intended"})) {
        my $out = ::check_tolerances($me->{'abstol'},
                                     $me->{'reltol'},
                                     $me->{'num'}.".".$me->{'name'});
        if (defined($out) && $out ne '') {
            Log(0, $out);
            return undef;
        }
    }
    $me->{'compwhite'}   = ${"${class}::compwhite"};
    $me->{'floatcompare'}= ${"${class}::floatcompare"};
    $me->{'obiwan'}      = ${"${class}::obiwan"};
    $me->{'skiptol'}     = ${"${class}::skiptol"};
    $me->{'skipabstol'}  = ${"${class}::skipabstol"};
    $me->{'skipreltol'}  = ${"${class}::skipreltol"};
    $me->{'skipobiwan'}  = ${"${class}::skipobiwan"};
    $me->{'binary'}      = ${"${class}::binary"};
    $me->{'ignorecase'}  = ${"${class}::ignorecase"};
    $me->{'dependent_workloads'}  = ${"${class}::dependent_workloads"} || 0;

    if (!defined(${"${class}::benchlang"}) || ${"${class}::benchlang"} eq '') {
        %{$me->{'BENCHLANG'}} = %{"${class}::benchlang"};
        @{$me->{'allBENCHLANG'}}= ();
        # Fix up the benchlang lists (so that they're lists), and make the
        # full list of all benchlangs
        foreach my $exe (keys %{$me->{'BENCHLANG'}}) {
            if (ref($me->{'BENCHLANG'}->{$exe}) eq 'ARRAY') {
                push @{$me->{'allBENCHLANG'}}, @{$me->{'BENCHLANG'}->{$exe}};
            } else {
                my @langs = split(/[\s,]+/, $me->{'BENCHLANG'}->{$exe});
                $me->{'BENCHLANG'}->{$exe} = [ @langs ];
                push @{$me->{'allBENCHLANG'}}, @langs;
            }
        }
    } else {
        @{$me->{'BENCHLANG'}}= split(/[\s,]+/, ${"${class}::benchlang"});
        @{$me->{'allBENCHLANG'}}= @{$me->{'BENCHLANG'}};
    }
    if ($::lcsuite =~ /cpu(?:2006|v6)/ &&
        grep { $_ eq 'F77' } @{$me->{'allBENCHLANG'}}) {
      # SPEC CPU uses F variables for F77 codes
      push @{$me->{'allBENCHLANG'}}, 'F';
    }

    # Set up the language-specific benchmark flags
    foreach my $blang ('', 'c', 'f', 'cxx', 'f77', 'fpp') {
      if (defined ${"${class}::bench_${blang}flags"}) {
        $me->{'BENCH_'.uc($blang).'FLAGS'} = ${"${class}::bench_${blang}flags"};
      }
    }
    $me->{'benchmark'}   = $me->{'num'}.'.'.$me->{'name'};
    $me->{'path'}        = $topdir;
    $me->{'base_exe'}    = [@{"${class}::base_exe"}];
    $me->{'EXEBASE'}     = [@{"${class}::base_exe"}];
    $me->{'config'}      = $config;
    $me->{'refs'}        = [ $me, $config ];
    $me->{'result_list'} = [ ];
    $me->{'added_files'} = { };
    $me->{'version'}     = ${"${class}::version"};
    $me->{'clean_between_builds'} = ${"${class}::clean_between_builds"} || 'no';
    for (qw( abstol reltol compwhite obiwan skiptol binary
             skipabstol skipreltol skipobiwan
             floatcompare ignorecase )) {
	$me->{$_} = '' if !defined $me->{$_};
    }
    if (!@{$me->{'base_exe'}}) {
	Log(0, "There are no executables listed in \@base_exe for ".$me->{'num'}.".".$me->{'name'}.".  Ignoring benchmark\n");
	return undef;
    }
    $me->{'srcalts'} = { };
    $me->{'srcsource'} = jp($me->path, $me->srcdir);

    return $me;
}

sub per_file_param_val {
    my ($me, $param, $size, $size_class, $tune, $file) = @_;
    my $val = $me->{$param};
    my $result;
    if (ref($val) eq 'HASH') {
	if (exists($val->{$size}) && ref($val->{$size}) eq 'HASH') {
	    $val = $val->{$size};
	} elsif (exists($val->{$size_class}) && ref($val->{$size_class}) eq 'HASH') {
	    $val = $val->{$size_class};
	}
	if (exists($val->{$tune}) && ref($val->{$tune}) eq 'HASH') {
	    $val = $val->{$tune};
	}
	if (exists $val->{$file}) {
	    $result = $val->{$file};
	} elsif (ref ($val->{'default'}) eq 'HASH' && 
		 exists $val->{'default'}{$file}) {
	    $result = $val->{'default'}{$file};
	}
	if (!defined $result) {
	    if (exists $val->{$tune} && ref($val->{$tune}) eq '') {
		$result = $val->{$tune};
	    } elsif (exists $val->{$size} && ref($val->{$size}) eq '') {
		$result = $val->{$size};
	    } elsif (exists $val->{$size_class} && ref($val->{$size_class}) eq '') {
		$result = $val->{$size_class};
	    } elsif (exists $val->{$file} && ref($val->{$file}) eq '') {
		$result = $val->{$file};
	    } else {
		$result = $val->{'default'};
	    }
	}
    } else {
	$result = $val;
    }
    return $result;
}
sub per_file_param {
    my $val = per_file_param_val(@_);
    return istrue($val)?1:undef;
}

sub compwhite    { shift->per_file_param('compwhite', @_); };
sub floatcompare { shift->per_file_param('floatcompare', @_); };
sub abstol       { shift->per_file_param_val('abstol', @_); };
sub reltol       { shift->per_file_param_val('reltol', @_); };
sub obiwan       { shift->per_file_param('obiwan', @_); };
sub skiptol      { shift->per_file_param_val('skiptol', @_); };
sub skipreltol   { shift->per_file_param_val('skipreltol', @_); };
sub skipabstol   { shift->per_file_param_val('skipabstol', @_); };
sub skipobiwan   { shift->per_file_param_val('skipobiwan', @_); };
sub binary       { shift->per_file_param('binary', @_); };
sub ignorecase   { shift->per_file_param_val('ignorecase', @_); };

sub instance {
    my ($me, $config, $tune, $size, $ext, $mach, $copies) = @_;

    my $child = bless { %$me }, ref($me);
    $child->{'config'} = $config;
    $child->{'tune'}  = $tune;
    $child->{'ext'}   = $ext;
    $child->{'size'}  = $size;
    $child->{'size_class'} = $me->get_size_class($size);
    $child->{'mach'}  = $mach;
    $child->{'result_list'} = [];
    $child->{'iteration'} = -1;
    my $bench = $child->benchmark;
    my @sets = $config->benchmark_in_sets($bench);
    $child->{'refs'} = [ $child,
			 reverse ($config,
				  $config->ref_tree('', ['default', @sets, $bench],
						    ['default', $tune],
						    ['default', $ext],
						    ['default', $mach])) ];

    if ($child->basepeak == 2 &&
	!exists($child->{'basepeak'})) {
	# We've inherited this weird setting from the top level, so ignore
	# it.
	$child->{'basepeak'} = 0;
    } else {
	$child->{'basepeak'} = istrue($child->basepeak);
    }
    if (istrue($child->{'basepeak'})) {
	$child->{'smarttune'} = 'base';
	$child->{'refs'} = [ $child,
			     reverse ($config,
				      $config->ref_tree('', ['default', @sets, $bench],
							['default', 'base'],
							['default', $ext],
							['default', $mach])) ];
    } else {
	$child->{'smarttune'} = $tune;
    }

    $child->{'srcalts'} = $me->srcalts;
    if (defined($copies) && $copies < 0) {
        # Get the count of copies via the ref tree.
        $copies = $child->accessor_nowarn('copies');
        $copies = $config->copies if (!defined($copies));
    }
    $copies = $child->copies if ($::lcsuite =~ /cpu(?:2006|v6)/ && $child->{'smarttune'} eq 'base');
    if (defined($copies) && ($copies > 0)) {
        $child->{'copylist'} = [$copies];
    } else {
        $copies = $child->accessor_nowarn('copylist');
        if (defined($copies) && ref($copies) eq 'ARRAY') {
            $child->{'copylist'} = $copies;
        } else {
            $child->{'copylist'} = [ 1 ];
        }
    }

    $child->{'ranks'} = $child->ranks($tune) if ($::lcsuite =~ /^(mpi2007)$/);
    $child->{'threads'} = $child->ranks($tune) if ($::lcsuite =~ /^(omp2012|cpuv6)$/);

    # Fix up the sources list, if necessary.  This isn't done in new() because
    # the benchmark may get its sources from another benchmark which hasn't
    # yet been instantiated at new() time.
    if ((::reftype($child->sources) ne 'ARRAY') && (::reftype($child->sources) ne 'HASH')) {
        # $child->sources contains the name of the benchmark whose sources
        # it will inherit.
        # Find out where the benchmark lives
        if (!exists ($child->benchmarks->{$child->sources})) {
            ::Log(0, "ERROR: Benchmark ".$child->sources." specified as source code source for ".$child->benchmark."\ncan not be found!\n");
            main::do_exit(1);
        }
        my $donor = $child->benchmarks->{$child->sources};
        my $tmptop = $donor->{'path'};
        $child->{'srcsource'} = jp($tmptop, $donor->srcdir);
        $child->{'sources'} = $donor->{'sources'};
        $child->{'srcalts'} = $donor->{'srcalts'};
        $child->{'deps'} = $donor->{'deps'};
    }

    if ($child->check_exe(1) || !$config->accessor_nowarn('nobuild')) {
        # Check the number of threads.  Maybe the benchmark can warn ahead of time
        # if the setting is bad.  Benchmark is responsible for logging any non-generic
        # error messages.
        if ($child->check_threads()) {
            ::Log(0, "ERROR: ".$me->name." (".$me->tune.") failed thread check with ".$child->{'threads'}." threads.\n");
            return undef;
        }
    }

    return $child;
}

sub descmode {
    my ($me, %opts) = @_;
    my @stuff = ();
    push @stuff, $me->benchmark unless $opts{'no_benchmark'};
    if (!$opts{'no_size'}) {
      my $size = $me->size;
      $size .= ' ('.$me->size_class.')' if ($me->size_class ne $size);
      push @stuff, $size;
    }
    push @stuff, $me->tune unless $opts{'no_tune'};
    push @stuff, $me->ext unless $opts{'no_ext'};
    push @stuff, $me->mach unless $opts{'no_mach'};
    push @stuff, 'threads:'.$me->{'threads'} unless ($opts{'no_threads'} || $me->{'threads'} <= 1);
    return join(' ', @stuff);
}

sub workload_dirs {
    my ($me, $head, $size, $direction) = @_;

    $direction = '' if $direction eq 'base';

    # The "all" directory is always involved
    my @dirs = ( jp($head, 'all', $direction) );

    return @dirs unless $size ne '';

    # The default also includes the size-specific workload data directory
    unshift @dirs, jp($head, $size, $direction);

    return @dirs unless exists($me->{'workload_dirs'}->{$size});

    # If there are directories from which this workload size should inherit
    # files, add them here.
    if ((::reftype($me->{'workload_dirs'}->{$size}) eq 'ARRAY')) {
        push @dirs, $me->handle_workload_dir_addition($head, $direction, $size, @{$me->{'workload_dirs'}->{$size}});
    } elsif ($me->{'workload_dirs'}->{$size} ne '') {
        push @dirs, $me->handle_workload_dir_addition($head, $direction, $size, $me->{'workload_dirs'}->{$size});
    }

    return @dirs;
}

sub handle_workload_dir_addition {
    my ($me, $head, $direction, $origsize, @dirs) = @_;
    my @rc = ();
    my %seen = ();

    foreach my $dir (@dirs) {
        if ((::reftype($dir) eq 'ARRAY')) {
            # Remote benchmark, with benchmark name and workload size
            my ($bmark, @sizes) = @{$dir};
            if (@sizes > 0) {
                push @sizes, 'all';
            } else {
                @sizes = ('', 'all');
            }
            if (!exists ($me->benchmarks->{$bmark})) {
                ::Log(0, "Benchmark $bmark specified as $origsize workload source for $me->benchmark\ncan not be found!  Ignoring...\n");
                next;
            }
            my $donor = $me->benchmarks->{$bmark};
            foreach my $size (@sizes) {
                next if exists($seen{$size.$bmark});
                $seen{$size.$bmark}++;
                $size = $origsize unless defined($size) && $size ne '';
                push @rc, jp($donor->{'path'}, $donor->datadir, $size, $direction);
            }
        } else {
            # Just a different size from the same benchmark
            push @rc, jp($head, $dir, $direction);
        }
    }

    return @rc;
}

sub input_files_hash {
    my ($me, $size, $showbz2) = @_;
    my $head = jp($me->path, $me->datadir);

    $size = $me->size if ($size eq '');

    my @candidate_dirs = $me->workload_dirs($head, $size, $me->inputdir);

    my @dirs = ();
    for my $dir (@candidate_dirs) {
        unshift (@dirs, $dir) if -d $dir;
    }
    my ($files, $dirs) = main::build_tree_hash($me, \%::file_md5, @dirs);

    # Change the names of the compressed files if showbz2 is false, in order
    # to give some clients (like invoke()) a picture of the input files as
    # they'll be presented to the benchmarks.
    if (!$showbz2) {
	foreach my $file (sort keys %$files) {
	    if ($file =~ s/\.bz2$//o) {
		$files->{$file} = $files->{$file.'.bz2'};
		delete $files->{$file.'.bz2'};
	    }
	}
    }

    # In the case of working in the working tree, it's necessary to weed out
    # sources of compressed files.
    foreach my $file (sort keys %$files) {
	if (exists $files->{$file.'.bz2'}) {
	    delete $files->{$file};
	}
    }
    return ($files, $dirs);
}

sub copy_input_files_to {
    my ($me, $fast, $size, $concurrent, $bind, @paths) = @_;
    my ($files, $dirs) = $me->input_files_hash($size, 1);
    if (!defined($files) || !defined($dirs)) {
	Log(0, "ERROR: couldn't get file list for $size input set\n");
	return 1;
    }

    # Make sure there's something to do
    return 0 unless (grep { defined } @paths);

    for my $dir (@paths) {
        next unless defined($dir);
	# Create directories
        eval {
            main::mkpath($dir, 0, 0755);
            for my $reldir (sort keys %$dirs) {
                main::mkpath(jp($dir, $reldir), 0, 0755);
            }
        };
        if ($@) {
            Log(0, "ERROR: couldn't create destination directories: $@\n");
            return 1;
        }
    }

    if ($concurrent <= 1 || @paths <= 1) {
        # Do this serially, either because there are efficiencies to be gained
        # by reading a file once and writing it many times, or because there's
        # only one directory to process.  Besides, this is tried-and-tested
        # code.
        # Copy files
        for my $file (sort keys %$files) {
            if (!main::copy_file($files->{$file}, $file, \@paths, !$fast)) {
                Log(0, "ERROR: couldn't copy $file for $size input set\n");
                return 1;
            }
        }
    } else {
        # Process files on a per-directory basis.  This results in more read
        # activity per source file, but as each dir will have its own process
        # hopefully the overhead will be offset by the parallelism.
        %::children = ();
        $::running = 0;
        $::child_loglevel = 10;
        my $start_time;
        for(my $i = 0; $i < @paths; $i++) {
            my $path = $paths[$i];
            next unless defined($path);
            my $pid = undef;
            if ($::running < $concurrent) {
                ($start_time, $pid) = ::runspec_fork($me, \%::children, $i,
                                                     'loglevel' => $::child_loglevel,
                                                     'bind' => $bind,
                                                     'parent_msg' =>"Started child (\$pid) to populate run directory for copy \$idx\n",
                                                     'child_msg' => "Populating run directory for copy \$idx: ".File::Basename::basename($path)."\n",
                                                     'log' => 1,
                                                    );
                if ($pid) {
                    $::children{$pid}->{'bench'} = $me;
                    next;
                }
            } else {
                # Wait a bit for kids to exit
                Time::HiRes::sleep 0.3;
                ::check_children('Setup');
                redo;	# Try again
            }
            for my $file (sort keys %$files) {
                if (!main::copy_file($files->{$file}, $file, [ $path ], !$fast)) {
                    Log($::child_loglevel, "ERROR: couldn't copy $file for $size input set\n");
                    exit(255);
                }
            }
	    Log($::child_loglevel, sprintf("Finished populating run directory for copy $i in %.3fs\n", Time::HiRes::time - $start_time));
	    main::close_log();
	    exit(0);
        }
	# Wait for children to exit
	while($::running > 0) {
            ::check_children('Setup');
            Time::HiRes::sleep 0.3;
	}
        ::check_children('Setup');      # Just in case
	foreach my $kidpid (keys %::children) {
	    my $idx = $::children{$kidpid}->{'idx'};
	    if (defined($idx)) {
		if ($::children{$kidpid}->{'rc'} > 0) {
		    Log(0, "ERROR: Execution error for setup:populate of copy $idx\n");
                    return 1;
		}
	    } else {
	    	Log(0, "ERROR: No directory index for setup:populate child PID $kidpid\n");
		return 1;
	    }
	}
    }

    return 0;
}

sub input_files_base {
    my $me = shift;
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub input_files {
    my $me = shift;
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub input_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->input_files_hash(@_);

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub output_files_hash {
    my ($me, $size) = @_;
    my $head = jp($me->path, $me->datadir);

    $size = $me->size if ($size eq '');

    my @candidate_dirs = $me->workload_dirs($head, $size, $me->outputdir);

    my @dirs = ();
    foreach my $dir (@candidate_dirs) {
      unshift (@dirs, $dir) if -d $dir;
    }

    return main::build_tree_hash($me, \%::file_md5, @dirs);
}

sub output_files_base {
    my $me = shift;
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub output_files {
    my $me = shift;
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub output_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->output_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub added_files_hash {
  my ($me) = @_;
  if (defined($me->{'added_files'}) && ref($me->{'added_files'}) eq 'HASH') {
    return $me->{'added_files'};
  } else {
    return {};
  }
}

sub added_files_base {
    my $me = shift;
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort keys %$hash;
}

sub added_files {
    my $me = shift;
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { $hash->{$_} } keys %$hash;
}

sub added_files_abs {
    my $me = shift;
    my $head   = jp($me->path, $me->datadir);
    my ($hash) = $me->added_files_hash;

    return undef unless ref($hash) eq 'HASH';
    return sort map { jp($head, $hash->{$_}) } keys %$hash;
}

sub exe_files {
    my $me    = shift;
    my $tune  = $me->smarttune;
    my $ext   = $me->ext;
    my $fdocommand = $me->accessor_nowarn('fdocommand');
    if (defined($fdocommand) && ($fdocommand ne '')) {
	return @{$me->base_exe};
    } else {
#	return map { "${_}_$tune$mach.$ext" } @{$me->base_exe};
	return map { "${_}_$tune.$ext" } @{$me->base_exe};
    }
}

sub exe_file {
    my $me = shift;
    return ($me->exe_files)[0];
}

sub exe_files_abs {
    my $me = shift;
    my $path = $me->path;
    if ($me->output_root ne '') {
      my $oldtop = ::make_path_re($me->top);
      my $newtop = $me->output_root;
      $path =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';
    my $head   = jp($path, $me->bindir, $subdir);
    return sort map { jp($head, $_) } $me->exe_files;
}

sub get_size_class {
    my ($me, $size) = @_;

    my @stuff = read_reftime('time', $me->workload_dirs(jp($me->path, $me->datadir), $size, 'base'));
    return $stuff[2];
}

sub reference {
    my $me = shift;
    my ($ref, $size, $size_class) = read_reftime('time', $me->workload_dirs(jp($me->path, $me->datadir), $me->size, 'base'));
    return 1 unless defined($ref);
    if ($size_class eq 'ref' && ($ref == 0)) {
	Log(0, "$size (ref) reference time for ".$me->descmode('no_size' => 1, 'no_threads' => 1)." == 0\n");
	return 1;
    };
    return $ref;
}

sub reference_power {
    my $me = shift;
    my ($ref, $junk) = read_reftime('power', $me->workload_dirs(jp($me->path, $me->datadir), $me->size, 'base'));
    return 1 unless defined($ref);
    return $ref;
}

sub read_reftime {
    my ($name, @dirs) = @_;
    my @missing = ();

    foreach my $dir (@dirs) {
        next if ($dir =~ m#[\\/]all[\\/]?$#); # 'all' never has a reftime file
        my $file = jp($dir, 'ref'.$name);

        if (!-f $file) {
            push @missing, $dir;
            next;
        };
        my @lines = main::read_file($file);
        chomp(@lines);
        my ($size, $size_class) = split(/\s+/, $lines[0], 2);
        $size_class = $size unless defined($size_class) && $size_class ne '';
        my $ref = $lines[1];

        return ($ref, $size, $size_class);
    }

    # If we get here, no reftime files were found, so log the whole list
    Log(0, "read_reftime: 'ref$name' could not be found in any of the following directories:\n   ".join("\n   ", @missing)."\n");
    return undef;
}

sub Log     { main::Log(@_); }
sub jp      { main::joinpaths(@_); }
sub istrue  { main::istrue(@_); }
sub src     { my $me = shift; return $me->{'srcsource'} };
sub apply_diff { main::apply_diff(@_); }
sub md5scalardigest { main::md5scalardigest(@_); }

sub check_md5 {
    my $me = shift;
    return 1 if istrue($me->reportable);
    return $me->accessor_nowarn('check_md5');
}

sub make {
    my $me = shift;
    return 'specmake' if istrue($me->reportable);
    return $me->accessor_nowarn('make');
}

sub make_no_clobber {
    my $me = shift;
    return 0 if istrue($me->reportable);
    return $me->accessor_nowarn('make_no_clobber');
}

# Check to make sure that the input set exists.
sub check_size {
    my ($me, $size) = @_;
    $size = $me->size unless defined($size) && $size ne '';
    my $datadir = jp($me->path, $me->datadir);

    my @dirs = $me->workload_dirs($datadir, $size, 'base');
    my $found = 0;
    for my $dir (grep { !m#[\\/]all[\\/]?$# } @dirs) {
        if (-f jp($dir, 'reftime')) {
            $found++;
            last;
        }
    }
    return 0 unless $found >= 1;        # reftime is necessary

    for my $direction ($me->inputdir, $me->outputdir) {
DIRS:   for my $dir (@dirs) {
            if (-d jp($dir, $direction)) {
                $found++;
                last DIRS;
            }
        }
    }
    return 1 if $found >= 3;        # Need inputs AND outputs

    return 0;
}

sub check_exe {
    my ($me, $exe_only) = @_;
    my $check_md5 = istrue($me->check_md5) || istrue($me->reportable);

    # If there are no MD5 hashes then, we will definitely fail the compare
    if ($check_md5 && ($me->accessor_nowarn('optmd5') eq '')) {
        Log(130, "When checking options for ".join(',', $me->exe_files_abs).", no MD5 sums were\n  found in the config file.  They will be installed after build.\n");
	return 0;
    }
    if ($check_md5 && ($me->accessor_nowarn('exemd5') eq '')) {
        Log(130, "When checking executables (".join(',', $me->exe_files_abs)."), no MD5 sums were\n  found in the config file.  They will be installed after build.\n");
	return 0;
    }

    # Build a hash of the executable files
    my $ctx = new Digest::MD5;

    for my $name (sort $me->exe_files_abs) {
        if ((! -e $name) || ($^O !~ /MSWin/i && ! -x $name)) {
          if (!-e $name) {
            Log(190, "$name does not exist\n");
          } elsif (!-x $name) {
            Log(190, "$name exists, but is not executable\n");
            Log(190, "stat for $name returns: ".join(', ', @{stat($name)})."\n") if (-e $name);
          }
          return 0;
        }
	my $fh = new IO::File "<$name";
	if (!defined $fh) {
	    Log (0, "Can't open file '$name' for reading: $!\n");
	} else {
            $ctx->addfile($fh);
        }
    }
    if ($check_md5) {
	my $md5exe = $ctx->hexdigest;
	if ($md5exe ne $me->accessor_nowarn('exemd5')) {
	    Log(130, "MD5 mismatch for executables (stored: ".$me->accessor_nowarn('exemd5').")\n");
	    return 0;
	}
        if (!$exe_only) {
            my $md5opt = $me->option_md5(1);
            if ($md5opt ne $me->accessor_nowarn('optmd5')) {
                Log(130, "MD5 mismatch for options (stored: ".$me->accessor_nowarn('optmd5').")\n");
                return 0;
            }
        }
    }
    return 1;
}

sub form_makefiles {
    my $me = shift;
    my %vars;
    my %deps;

    my $tune  = $me->smarttune;
    my $ext   = $me->ext;
    my $bench = $me->benchmark;

    my $srcref = $me->sources;
    my %sources;
    my @targets;

    if (ref($srcref) eq 'ARRAY') {
	$sources{$me->EXEBASE->[0]} = [ @{$srcref} ];
	@targets = ($me->EXEBASE->[0]);
    } else {
	%sources = %{$srcref};
	@targets = sort keys %{$srcref};
    }

    my @output_files = ();
    if (istrue($me->feedback)) {
        # Assume that it's okay.  If it's not, the run will be stopped after
        # the makefiles are formed.  In any case, the list of output files
        # we're adding here is just for the benefit of fdoclean, which won't
        # happen unless FDO is happening.
        my ($filehash) = $me->output_files_hash($me->train_with);
        @output_files = sort keys %{$filehash} if (::reftype($filehash) eq 'HASH');
    }

    foreach my $exe (@targets) {
	$vars{$exe} = [];
	push @{$vars{$exe}}, "TUNE=". $tune;
	push @{$vars{$exe}}, "EXT=".  $ext;
	# Do the stuff that used to be in src/Makefile
	push @{$vars{$exe}}, "NUMBER=". $me->num;
	push @{$vars{$exe}}, "NAME=". $me->name;
	push @{$vars{$exe}}, ::wrap_join(75, ' ', "\t ", " \\",
					     ('SOURCES=', @{$sources{$exe}}));
	push @{$vars{$exe}}, "EXEBASE=$exe";
	push @{$vars{$exe}}, 'NEED_MATH='.$me->need_math;
        my @benchlang;
        if (ref($me->BENCHLANG) eq 'HASH') {
            if (!exists($me->BENCHLANG->{$exe})) {
                Log(0, "ERROR: No benchlang is defined for target $exe\n");
                main::do_exit(1);
            }
            if (ref($me->BENCHLANG->{$exe}) eq 'ARRAY') {
                @benchlang = @{$me->BENCHLANG->{$exe}};
            } else {
                @benchlang = split(/[\s,]+/, $me->BENCHLANG->{$exe});
            }
            push @{$vars{$exe}}, 'BENCHLANG='.join(' ', @benchlang);
        } else {
            @benchlang = @{$me->BENCHLANG};
            push @{$vars{$exe}}, 'BENCHLANG='.join(' ', @benchlang);
        }
        # Do ONESTEP (or not)
        foreach my $chance ('ONESTEP', $benchlang[0].'ONESTEP') {
          my $onestep = $me->accessor_nowarn($chance);
          if (istrue($onestep)
              && (($::lcsuite =~ /cpu(?:2006|v6)/ && $tune eq 'base')
                  ||
                  ($::lcsuite =~ /mpi2007/ && $tune eq 'base')
                  ||
                  ($::lcsuite =~ /omp(?:2001|2012)/ && $tune eq 'base'))
             ) {
            Log(0, "ERROR: $chance is not allowable in a $tune build.  Ignoring $chance setting\n");
            Log(0, "       for $bench $tune $ext\n");
            push @{$vars{$exe}}, $chance.'=';
          } else {
            push @{$vars{$exe}}, $chance.'='.$onestep;
          }
        }
	push @{$vars{$exe}}, '';

	foreach my $var (sort $me->list_keys) {
            # Exclude some variables that we don't want in the makefile
	    next if $var =~ /^(?:(?:pp|raw)txtconfig|oldmd5|cfidx_|toolsver|baggage|compile_options|rawcompile_options|exemd5|optmd5|flags(?:url)?|(?:C|F|F77|CXX)?ONESTEP|ref_added|nc\d*$|nc_is_(?:cd|na)|BENCHLANG|sources)/;
	    my $val = $me->accessor($var);

	    # Don't want references in makefile either
	    if (ref ($val) eq '') {
		# Escape the escapes
		$val =~ s/\\/\\\\/go;
		$val =~ s/(\r\n|\n)/\\$1/go;
		$val =~ s/\#/\\\#/go;
		push (@{$vars{$exe}}, sprintf ('%-16s = %s', $var, $val));
	    } elsif ((::reftype($val) eq 'HASH')) {
                if (exists($val->{$exe})) {
                    push (@{$vars{$exe}}, sprintf ('%-16s = %s', $var, $val->{$exe}));
                } # else ignore it
            }
	}
        push @{$vars{$exe}}, sprintf ('%-16s = %s', 'OUTPUT_RMFILES', join(' ', @output_files));

	# Add vendor makefile stuff at the end
	if ($me->accessor_nowarn('vendor_makefile') ne '') {
	    push (@{$vars{$exe}}, $me->vendor_makefile);
	}
	$vars{$exe} = join ("\n", @{$vars{$exe}}) . "\n";

        # Add in dependencies, if any
        push @{$deps{$exe}}, '','# These are the build dependencies', '';
        my (%objdeps, %srcdeps);
        if (exists($me->deps->{$exe}) &&
            (::reftype($me->deps->{$exe}) eq 'HASH')) {
            %objdeps = %{$me->deps->{$exe}};
        } else {
            %objdeps = %{$me->deps};
        }
        if (exists($me->srcdeps->{$exe}) &&
            (::reftype($me->srcdeps->{$exe}) eq 'HASH')) {
            %srcdeps = %{$me->srcdeps->{$exe}};
        } else {
            %srcdeps = %{$me->srcdeps};
        }

        # Object dependencies are for things like F9x modules which must
        # actually be built before the object in question.
        foreach my $deptarget (keys %objdeps) {
            my $deps = $objdeps{$deptarget};
            my (@normaldeps, @ppdeps);

            # Coerce the dependencies into a form that we like
            if (ref($deps) eq '') {
               # Not an array, just a single entry
               $deps = [ $deps ];
            } elsif (ref($deps) ne 'ARRAY') {
                Log(0, "WARNING: Dependency value for $deptarget is not a scalar or array; ignoring.\n");
                next;
            }

            # Figure out which will need to be preprocessed and which won't
            foreach my $dep (@{$deps}) {
              if ($dep =~ /(\S+)\.F(90|95|)$/o) {
                push @ppdeps, "$1.fppized";
              } else {
                push @normaldeps, $dep;
              }
            }

            # Change the name of the target, if necessary
            my ($ppname, $fulltarget) = ($deptarget, '');
            if ($deptarget =~ /(\S+)\.F(90|95|)$/o) {
              $fulltarget = "$1.fppized";
              $ppname = "$fulltarget.f$2";
            } else {
              $fulltarget = "\$(basename $deptarget)";
            }

            # The end result
            push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), $fulltarget): $ppname \$(addsuffix \$(OBJ),\$(basename ".join(' ', @normaldeps).") ".join(' ', @ppdeps).")";
        }

        # Source dependencies are for things like #include files for C
        foreach my $deptarget (keys %srcdeps) {
            my $deps = $srcdeps{$deptarget};
            if (ref($deps) eq '') {
                push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), \$(basename $deptarget)): $deptarget $deps";
            } elsif (ref($deps) eq 'ARRAY') {
                push @{$deps{$exe}}, "\$(addsuffix \$(OBJ), \$(basename $deptarget)): $deptarget ".join(' ', @{$deps});
            } else {
                Log(0, "WARNING: Dependency value for $deptarget is not a scalar or array; ignoring.\n");
            }
        }
        push @{$deps{$exe}}, '# End dependencies';
    }

    foreach my $exe (keys %deps) {
        $deps{$exe} = join ("\n", @{$deps{$exe}}) . "\n";
    }
    if (@targets == 1) {
        # No per-executable deps
        $deps{''} = $deps{$targets[0]};
        delete $deps{$targets[0]};
    }
    return (\%deps, %vars);
}

sub write_makefiles {
    my ($me, $path, $varname, $depname, $no_write, $no_log) = @_;
    my @files = ();
    my ($deps, %vars) = $me->form_makefiles;
    my ($filename, $fh);

    if (!$no_write) {
        # Dump the dependencies
        foreach my $exe (sort keys %{$deps}) {
            my $tmpname = $depname;
            my $tmpexe = $exe;
            $tmpexe .= '.' unless ($exe eq ''); # Add the trailing .
            $tmpname =~ s/%T/$tmpexe/;
            $filename = jp($path, $tmpname);
            Log (150, "Wrote to makefile '$filename':\n", \$deps->{$exe}) unless $no_log;
            $fh = new IO::File;
            if (!$fh->open(">$filename")) {
                Log(0, "Can't write makefile '$filename': $!\n");
                main::do_exit(1);
            }
            $fh->print($deps->{$exe});
            $fh->close();
            if (-s $filename < length($deps->{$exe})) {
              Log(0, "\nERROR: $filename is short!\n       Please check for sufficient disk space.\n");
              main::do_exit(1);
            }
        }
    }

    my @targets = sort keys %vars;
    foreach my $target (sort keys %vars) {
	# Dump the variables
	$filename = jp($path, $varname);
	# Benchmarks with a single executable get 'Makefile.spec'; all
	# others get multiple makefiles with the name of the target
	# in the filename.
	if ($target eq $me->baseexe && (@targets+0) == 1) {
	    $filename =~ s/YYYtArGeTYYYspec/spec/;
	} else {
	    $filename =~ s/YYYtArGeTYYYspec/${target}.spec/;
	}
        if (!$no_write) {
          $fh = new IO::File;
          if (!$fh->open(">$filename")) {
              Log(0, "Can't write makefile '$filename': $!\n");
              main::do_exit(1);
          }
          Log (150, "Wrote to makefile '$filename':\n", \$vars{$target}) unless $no_log;
          $fh->print($vars{$target});
          $fh->close();
          if (-s $filename < length($vars{$target})) {
            Log(0, "\nERROR: $filename is short!\n       Please check for sufficient disk space.\n");
            main::do_exit(1);
          }
        }
	push @files, $filename;
    }
    return @files;
}

sub option_md5 {
    my ($me, $no_log, $opts) = @_;
    $no_log = 0 unless defined($no_log);
    $opts = $me->get_options($no_log) unless $opts ne '';

    my $md5 = new Digest::MD5;
    # WHY can I get away with splitting on just '\n'?  read_compile_options
    # normalizes all line endings to \n!
    foreach my $line (split(/\n/, $opts)) {
        # Normalize whitespace
        $line =~ tr/ \012\015\011/ /s;
        $md5->add($line);
    }
    my $rc = $md5->hexdigest;

    return $rc;
}

# Generate a list of build options that would actually be used for a benchmark.
# Lots of this code is similar to what's in build(), so changes there _may_
# need to be reflected here.
sub get_options {
    my ($me, $no_log) = @_;
    my $origwd = main::cwd();
    my $top = $me->top;

    # Binaries built using make_no_clobber aren't usable for reportable
    # runs, so make sure that we get a value of '0' for make_no_clobber
    # if reportable is set.
    if (istrue($me->reportable)) {
        $me->{'make_no_clobber'} = 0;
    }

    # Now generate options from specmake
    my $tmpdir = ::get_tmp_directory($me, 1, 'options.'.$me->num.'.'.$me->name.'.'.$me->tune);
    if ( ! -d $tmpdir ) {
        # Something went wrong!
        Log(0, "ERROR: Temporary directory \"$tmpdir\" couldn't be created\n");
        return undef;
    }
    chdir($tmpdir);

    my $langref = {};
    if ($me->smarttune eq 'base') {
	$langref->{'FPBASE'} = 'yes';
    }
    $langref->{'commandexe'} = ($me->exe_files)[0];
    $langref->{'baseexe'} = ($me->base_exe)[0]->[0];
    $me->unshift_ref($langref);

    # Do pre-build stuff (but not for real)
    if ($me->pre_build($tmpdir, 0, undef, undef)) {
        Log(0, "\n\nERROR: benchmark pre-build function failed\n\n");
        $me->shift_ref;
        return undef;
    }

    # Actually write out the makefiles and get a list of targets
    my @makefiles = $me->write_makefiles($tmpdir, $me->specmake,
					 'Makefile.%Tdeps', 0, $no_log);
    my @targets = map { basename($_) =~ m/Makefile\.(.*)\.spec/o; $1 } @makefiles;

    # What's make?
    my $make = $me->make;
    my $makeflags = ' '.$me->makeflags if ($me->makeflags ne '');

    # Check to see if feedback is being used.  Similar (nay, identical!) to
    # the code near line 1428 or so.  Changes should be mirrored.
    my @pass = ();
    my $fdo = 0;
    if (istrue($me->feedback)) {
	for my $tmpkey ($me->list_keys) {
	    if    ($tmpkey =~ m/^fdo_\S+?(\d+)/p   && $me->accessor_nowarn(${^MATCH}) ne '') { 
		$pass[$1] = 1; $fdo = 1; 
	    }
            elsif ($tmpkey =~ m/^PASS(\d+)_(\S+)/p && $me->accessor_nowarn(${^MATCH}) ne '')    { 
		my ($pass, $what) = ($1, $2);
		$what =~ m/^(\S*)(FLAGS|OPTIMIZE)/;
		if ($1 ne 'LD' && !grep { $_ eq $1 } @{$me->allBENCHLANG}) {
		    next;
		}
		$pass[$pass] = 1; $fdo = 1; 
	    }
	}
    }
    if ($fdo) {
        $fdo = 0 if ($::lcsuite eq 'mpi2007');
        $fdo = 0 if ($me->smarttune eq 'base');
    }

    my ($fdo_defaults, @commands);
    if ($fdo) {
        ($fdo_defaults, @commands) = $me->fdo_command_setup(\@targets, $make.$makeflags, @pass);
        $me->push_ref($fdo_defaults);
    } else {
        @pass = ( 0 );
        # Somewhat magical value(s) for non-FDO builds
        @commands = map { 'fdo_make_pass_'.$_ } @targets;
    }

    # Add in mandatory options
    my $options = $me->get_mandatory_option_md5_items(($fdo) ? 'train_with' : '');

    my $rc = 0;
    foreach my $cmd (@commands) {
        my $val = $me->accessor_nowarn($cmd);
        my $pass = '';
        my $target = '';
        if ($cmd =~ m/^fdo_make_pass(\d*)_(.*)$/) {
          $pass = $1;
          $target = $2;
        } elsif ($cmd =~ m/(\d+)$/) {
          $pass = $1;
        }
        next if $fdo && $val =~ m/^\s*$/;
        if ($cmd =~ /^fdo_run/) {
            $options .= "RUN$pass: $val\n" if $fdo;
        } else {
            if ($fdo) {
                # Don't record options whose default values have not been
                # overridden by the user.  This will keep changes in
                # makeflags (for example) from causing rebuilds.  This mimics
                # the v1.0 behavior.
                $options .= "$cmd: $val\n" if ($val ne $fdo_defaults->{$cmd});
            } elsif ($target ne '') {
                $options .= "Options for ${target}:\n";
            }
            if ($cmd =~ m/^fdo_make_pass/) {
                my $exe = ($target ne '') ? ".$target" : '';
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                my $passflag = ($pass ne '') ? " FDO=PASS$pass" : '';
                my $file = "options$pass$exe";
                $rc = main::log_system("$make -f $top/benchspec/Makefile.defaults options$targetflag$passflag",
                                       $file,
                                       0,
                                       [ { 'teeout' => 0 }, $me ],
                                       0, 1);
                if ($rc) {
                    Log(0, "\n\nERROR running '$make options$targetflag$passflag'\n\n");
                    $me->shift_ref;
                    return undef;
                }
                $options .= read_compile_options("${file}.out", $pass, 0);
                unlink "${file}.out" unless istrue($me->accessor_nowarn('keeptmp'));
            }
        }
    }
    unlink @makefiles unless istrue($me->accessor_nowarn('keeptmp'));

    chdir($origwd); # Back from whence we came
    File::Path::rmtree($tmpdir, 0, 1) unless istrue($me->accessor_nowarn('keeptmp'));

    if (!$no_log) {
        Log(30, "option_md5 list contains ------------------------------------\n");
        Log(30, "$options"); 
        Log(30, "------------------------------------ end option_md5 list\n");
    }
    return $options;
}

sub build {
    my ($me, $directory, $setup) = @_;
    my ($fdo);
    my $rc;
    my $bench = $me->benchmark;
    my @pass;
    my $makefile_md5;
    my $valid_build = 1;
    my $compile_options = '';
    my $path = $directory->path;
    my $ownpath = $me->path;
    if ($me->output_root ne '') {
      my $oldtop = ::make_path_re($me->top);
      my $newtop = $me->output_root;
      $ownpath =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';
    my $no_clobber = istrue($me->make_no_clobber);

    $valid_build = 0 if istrue($me->fake);

    # Get a pointer to where we update our build status info
    my $md5ref    = $me->config;
    for my $key ($me->benchmark, $me->smarttune, $me->ext, $me->mach) {
	if (!exists $md5ref->{$key} || ref($md5ref->{$key} ne 'HASH')) {
	    $md5ref->{$key} = {};
	}
	$md5ref = $md5ref->{$key};
    }
    $md5ref->{'changedmd5'} = 0;
    my $baggage;
    if (defined($md5ref->{'baggage'})) {
	$baggage = $md5ref->{'baggage'};
    } else {
	$baggage = '';
    }
    $md5ref->{'baggage'} = '';

    if (!istrue($me->fake) && !istrue($me->make_no_clobber)) {
      # First things first, remove any existing binaries with these names,
      # this makes sure that if the build fails any pre-existing binaries are
      # erased
      for my $file ($me->exe_files_abs) {
          if (-f $file && !unlink $file) {
              Log(0, "Can't remove file '$file': $!\n");
              main::do_exit(1);
          }
      }
    }

    if (istrue($me->accessor_nowarn('fail')) ||
        istrue($me->accessor_nowarn('fail_build'))) {
        Log(0, "ERROR: fail or fail_build set for this benchmark\n");
        $me->release($directory);
        $me->compile_error_result('CE', 'failed by request');
        return 1;
    }

    my $langref = {};
    if ($me->smarttune eq 'base') {
	$langref->{'FPBASE'} = 'yes';
    }
    $langref->{'commandexe'} = ($me->exe_files)[0];
    $langref->{'baseexe'} = ($me->base_exe)[0]->[0];
    $me->unshift_ref($langref);

    if ( $setup ||
         ! istrue($me->make_no_clobber) || 
	 ! -f jp ( $path, 'Makefile' )) {
        $no_clobber = 0;        # Must turn this off for makefiles to be made
	if (!::rmpath($path)) {	# It's probably not there
            eval { main::mkpath($path) };
            if ($@) {
                Log(0, "ERROR: Cannot create build directory for ".$me->benchmark.": $@\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', 'COULD NOT CREATE BUILD DIRECTORY');
                return 1;
            }
	}

        if (! -d $me->src()) {
            Log(0, "ERROR: src subdirectory (".$me->src().") for ".$me->benchmark." is missing!\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'MISSING src DIRECTORY');
            return 1;
        }
        # Copy the src directory, but leave out the src.alts
        if (!main::copy_tree($me->src(), $directory->path(), undef, [qw(src.alt CVS .svn)], !istrue($me->strict_rundir_verify))) {
            Log(0, "ERROR: src directory for ".$me->benchmark." contains corrupt files.\n");
            Log(0, "       Is your SPEC $::suite distribution corrupt, or have you changed any\n");
            Log(0, "       of the files listed above?\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'CORRUPT src DIRECTORY');
            return 1;
        }
        if ($me->pre_build($directory->path(), 1, undef, undef)) {
            Log(0, "ERROR: pre-build setup failed for ".$me->benchmark."\n");
            $me->shift_ref;
            $me->release($directory);
            $me->compile_error_result('CE', 'pre-build FAILED');
            return 1;
        }

##################################
# This is where we apply src.alts!
##################################
        my @srcalts = $me->get_srcalt_list();

        # This happens in several stages.  First, make sure that all the
        # src.alts that have been asked for are available.
        my $srcalt_applied = 0;
        foreach my $srcalt (@srcalts) {
            if (!exists($me->srcalts->{$srcalt})) {
                Log(103, "ERROR: Requested src.alt \"$srcalt\" does not exist!  Build failed.\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', "src.alt \"$srcalt\" not found");
                return 1;
            }
        }
        my %touched = ();
        # Next, copy all of the _new_ files from all of the src.alts into
        # the source directory.  Don't just copy blindly; do only the ones
        # listed as new in the src.alt.  (This is to not cause errors
        # when testing against the original src.alt directory.)
        # Though it should NOT be possible for a src.alt to modify a file
        # introduced by another (since the file won't have been in the
        # original src directory when the src.alt was made), let's be sort
        # of safe and mark all of the new ones as touched.
        my $top = $me->top;
        foreach my $srcalt (@srcalts) {
            my $saref = $me->srcalts->{$srcalt};
            my $srcaltpath = jp($me->src(), 'src.alt', $saref->{'name'});
            my $dest = $directory->path();
            foreach my $newfile (grep { m{^(?:$top[/\\]?)?benchspec[/\\]}o } sort keys %{$saref->{'filesums'}}) {
                # Skip README files; if there are multiple src.alts, one will
                # stomp the other, and chaos will ensue.
                next if $newfile =~ m{/README$};
                my $shortpath = $newfile;
                $shortpath =~ s{$srcaltpath[/\\]?}{};
                # Each "new" file's path will start will benchspec/
                if (!main::copy_file($newfile, $shortpath, [ $dest ],
                                     $::check_integrity && istrue($me->strict_rundir_verify), $saref->{'filesums'})) {
                    Log(0, "ERROR: src.alt \'$saref->{'name'}\' contains corrupt files.\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'CORRUPT src.alt DIRECTORY');
                    return 1;
                } else {
                    $touched{jp($dest, $shortpath)}++;
                }
            }
        }

        # Now that all the files have been copied in, apply the diffs to
        # the existing files.
        foreach my $srcalt (@srcalts) {
            my $saref = $me->srcalts->{$srcalt};
            my $srcaltpath = jp($me->src(), 'src.alt', $saref->{'name'});
            my $dest = $directory->path();
            foreach my $difffile (sort keys %{$saref->{'diffs'}}) {
                my $difftext = decode_base64($saref->{'diffs'}->{$difffile});
                if ($::check_integrity) {
                    my $diffsum = md5scalardigest($difftext);
                    if ($diffsum ne $saref->{'diffsums'}->{$difffile}) {
                        Log(0, "ERROR: src.alt \'$saref->{'name'}\' contains corrupt difference information.\n");
                        $me->shift_ref;
                        $me->release($directory);
                        $me->compile_error_result('CE', 'CORRUPT src.alt CONTROL FILE DIFFS (SUMS)');
                        return 1;
                    }
                }
                my $hunks;
                eval $difftext;
                if ($@) {
                    Log(0, "ERROR: src.alt \'$saref->{'name'}\' has corrupted control file.\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'CORRUPT src.alt CONTROL FILE DIFFS (SYNTAX)');
                    return 1;
                }

                my ($newsum, $offset, $ok) = apply_diff(jp($dest, $difffile), $hunks);
                # Application failed if application of diff
                # 1. failed (duh)
                # 2. succeeded with offset and file not previously touched
                # 3. succeeded with no offset and MD5 mismatch
                if (!$ok ||
                    (!$touched{$difffile} && ($offset ||
                    ($newsum ne $saref->{'filesums'}->{$difffile})))) {
                    if (!$ok) {
                        Log(0, "ERROR: application of diff failed\n");
                    } elsif (!$touched{$difffile} && $offset) {
                        Log(0, "ERROR: diff application offsets needed for previously untouched file\n");
                    } elsif (!$touched{$difffile} && ($newsum ne $saref->{'filesums'}->{$difffile})) {
                        Log(0, "ERROR: MD5 sum mismatch for previously untouched file\n");
                    }
                    Log(0, "ERROR: application of src.alt \'$saref->{'name'}\' failed!\n");
                    $me->shift_ref;
                    $me->release($directory);
                    $me->compile_error_result('CE', 'src.alt APPLICATION FAILED');
                    return 1;
                }
                $touched{$difffile}++;
            }
            # If we get to here, the src.alt was applied successfully
            my $tmpstr = $me->note_srcalts($md5ref, 0, $srcalt);
            Log(0, "$tmpstr\n") if $tmpstr ne '';
        }
	my $origmakefile = jp($me->src,"Makefile.${main::lcsuite}");
	$origmakefile = jp($me->src,'Makefile') if (!-f $origmakefile);
	if (!main::copy_file($origmakefile, 'Makefile', [$path], istrue($me->strict_rundir_verify))) {
	  Log(0, "ERROR: Failed copying makefile into build directory!\n");
	  $me->shift_ref;
	  $me->release($directory);
	  $me->compile_error_result('CE', 'Build directory setup FAILED');
	  return 1;
	}
    } else {
	$valid_build = 0;
    }

    if (!chdir($path)) {
	Log(0, "Couldn't chdir to $path: $!\n");
    }

    main::monitor_shell('build_pre_bench', $me);

    my @makefiles = $me->write_makefiles($path, $me->specmake,
					 'Makefile.%Tdeps', $no_clobber, 0);
    my @targets = map { basename($_) =~ m/Makefile\.(.*)\.spec/o; $1 } @makefiles;

    if ($setup) {
      $me->release($directory);
      return 0;
    }

    my $compile_start = time;  ## used by the following log statement
    Log(160, "  Compile for '$bench' started at: ".::ctime($compile_start)." ($compile_start)\n");

    my $make = $me->make;
    $make .= ' -n' if istrue($me->fake);
    $make .= ' '.$me->makeflags if ($me->makeflags ne '');

    # Check to see if feedback is being used.  Similar (nay, identical!) to
    # the code near line 1086 or so.  Changes should be mirrored.
    if (istrue($me->feedback)) {
	for my $tmpkey ($me->list_keys) {
	    if    ($tmpkey =~ m/^fdo_\S+?(\d+)/p   && $me->accessor_nowarn(${^MATCH}) ne '') { 
		$pass[$1] = 1; $fdo = 1; 
	    }
            elsif ($tmpkey =~ m/^PASS(\d+)_(\S+)/p && $me->accessor_nowarn(${^MATCH}) ne '')    { 
		my ($pass, $what) = ($1, $2);
		$what =~ m/^(\S*)(FLAGS|OPTIMIZE)/;
		if ($1 ne 'LD' && !grep { $_ eq $1 } @{$me->allBENCHLANG}) {
		    next;
		}
		$pass[$pass] = 1; $fdo = 1; 
	    }
	}
    }

    # Feedback is not allowed at all in MPI2007
    if ($fdo && $::lcsuite eq 'mpi2007') {
        Log(0, "WARNING: Feedback-directed optimization is not allowed. FDO directives\n");
        Log(0, "         will be ignored.\n");
        undef @pass;
        $fdo = 0;
    }

    # Feedback is only allowed in peak for CPU
    if ($fdo && $me->smarttune eq 'base') {
        Log(0, "WARNING: Feedback-directed optimization is not allowed for base tuning;\n");
        Log(0, "         Ignoring FDO directives for this build.\n");
        undef @pass;
        $fdo = 0;
    }

    # Feedback builds must use a training workload that exists
    if ($fdo && !$me->check_size($me->train_with)) {
        Log(0, "ERROR: $me->{'name'} does not support training workload ". $me->train_with. " (specified by train_with)\n");
        $me->release($directory);
        $me->compile_error_result('CE', 'train_with specifies non-existent workload');
        return 1;
    }

    # Feedback builds must use a training workload that's classified as one
    if ($fdo && $me->get_size_class($me->train_with) ne 'train') {
        Log(0, "ERROR: The workload specified by train_with MUST be a training workload!\n");
        $me->release($directory);
        $me->compile_error_result('CE', 'train_with specifies non-training workload '. $me->train_with);
        return 1;
    }

    # Add in mandatory stuff to compile options
    $compile_options = $me->get_mandatory_option_md5_items(($fdo) ? 'train_with' : '');

    # Set up some default values for FDO, don't set these if the user has
    # overridden them
    my ($fdo_defaults, @commands) = $me->fdo_command_setup(\@targets, $make, @pass);
    $me->push_ref($fdo_defaults);
    my %replacements = (
	    'benchmark' => $me->benchmark,
	    'benchtop'  => $me->path,
	    'benchnum'  => $me->num,
	    'benchname' => $me->name,
	    'spectop'   => $me->top,
    );

    my $tmp;
    foreach my $target (@targets) {
        next if istrue($no_clobber);
	my $targetflag = ($target ne '') ? " TARGET=$target" : '';
	my $file = ($target ne '') ? "make.clean.$target" : 'make.clean';
	if (main::log_system("$make clean$targetflag", $file, 0, [ $me, \%replacements ], 0)) {
	    $tmp = "Error with make clean!\n";
	    Log(0, "  $tmp") if $rc;
	    $me->pop_ref;
	    $me->shift_ref;
	    $me->release($directory);
	    $me->compile_error_result('CE', $tmp);
	    return 1;
	}
    }

    if ($fdo) {
	my $reason = undef;
	$me->unshift_ref({ 'size'          => $me->train_with });
	$rc = $me->copy_input_files_to(!istrue($me->strict_rundir_verify), $me->train_with, 1, '', $path);
        if ($me->post_setup($path)) {
            Log(0, "training post_setup for " . $me->benchmark . " failed!\n");
        };

	$me->shift_ref();
	if ($rc) {
	    $tmp = "  Error setting up training run!\n";
	    Log(0, $tmp);
	    $reason = 'FE';
	} else {
	    for my $cmd (@commands) {
		my $val = $me->accessor_nowarn($cmd);
		my $pass = '';
                my $target = '';
                if ($cmd =~ m/^fdo_make_pass(\d+)_(.+)$/) {
                  $pass = $1;
                  $target = $2;
                } elsif ($cmd =~ m/(\d+)$/) {
                  $pass = $1;
                }
		next if $val =~ m/^\s*$/;

                # Pre-build cleanup and setup (possibly)
                if ($cmd =~ m/^fdo_make_pass/) {
                    # Inter-build clean, if the benchmark calls for it
                    if (@targets > 1 && istrue($me->clean_between_builds)) {
                        foreach my $target (@targets) {
                            my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                            my $file = ($target ne '') ? "make.objclean.$target" : 'make.clean';
                            if (main::log_system("$make objclean$targetflag", $file, 0, [ $me, \%replacements ], 0)) {
                                $tmp = "Error with make objclean!\n";
                                Log(0, "  $tmp") if $rc;
                                $me->pop_ref;
                                $me->shift_ref;
                                $me->release($directory);
                                $me->compile_error_result('CE', $tmp);
                                return 1;
                            }
                        }
                    }

                    if ($me->pre_build($directory->path(), 1, $target, $pass)) {
                        # Do pre-build for each target
                        Log(0, "ERROR: pre-build setup failed for $target (pass $pass) in ".$me->benchmark."\n");
                        $me->shift_ref;
                        $me->release($directory);
                        $me->compile_error_result('CE', 'pre-build FAILED');
                        return 1;
                    }
                }

		if ($cmd =~ /^fdo_run/) {
		    $me->unshift_ref({
			'size'          => $me->train_with,
			'dirlist'       => [ $directory ],
			'fdocommand'    => $val });
		    Log(3, "Training ", $me->benchmark, ' with the ', $me->train_with. " workload\n");
		    $rc = $me->run_benchmark(1, 0, 1, undef, 1);
		    $me->shift_ref();
		    $compile_options .= "RUN$pass: $val\n";
		    if ($rc->{'valid'} ne 'S' && !istrue($me->fake)) {
			$tmp = "Error ($rc->{'valid'}) with training run!\n";
                        Log(0, "  $tmp");
			$reason = 'FE';
			last;
		    }
		} else {
                    my $really_fake = 0;
                    my $fake_cmd = substr($val, 0, 35);
                    $fake_cmd .= '...' if length($fake_cmd) >= 35;
                    $fake_cmd = "$cmd ($fake_cmd)";
                    if (istrue($me->fake) && $val !~ /$make/) {
                      $really_fake = 1;
                      Log(0, "\n%% Fake commands from $fake_cmd:\n");
                    }
		    $rc = main::log_system($val, $cmd, $really_fake,
					   [ $me, \%replacements ],
                                           0);
                    Log(0, "%% End of fake output from $fake_cmd\n\n") if $really_fake;

                    # Don't record options whose default values have not been
                    # overridden by the user.  This will keep changes in
                    # makeflags (for example) from causing rebuilds.  This
                    # mimics the v1.0 behavior.
                    $compile_options .= "$cmd: $val\n" if ($val ne $fdo_defaults->{$cmd});
		    if (($rc == 0) && $cmd =~ m/^fdo_make_pass/) {
                        # Since only one target was built, it's not necessary
                        # to generate options for all of them.
                        my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                        my $file = "options$pass";
                        $file .= ".$target" if ($target ne '');
                        $rc = main::log_system("$make options$targetflag FDO=PASS$pass",
                                               $file,
                                               $really_fake,
                                               [ $me, \%replacements ],
                                               0);
                        if ($rc && !istrue($me->fake)) {
                            $tmp = "Error with $cmd!\n";
                            Log(0, "  $tmp");
                            $reason = 'CE';
                            last;
                        }
                        $compile_options .= read_compile_options("${file}.out", $pass, 0);
		    } elsif ($rc && !istrue($me->fake)) {
                        $tmp = "Error with $cmd!\n";
                        Log(0, "  $tmp");
                        $reason = 'CE';
                        last;
                    }
		}
	    }
	    if ($rc && !istrue($me->fake)) {
		$me->pop_ref;
		$me->shift_ref;
		$me->release($directory);
		$me->compile_error_result($reason, $tmp);
		log_finish($bench, $compile_start);
		return 1;
	    }
	}
    } else {
	foreach my $target (@targets) {
            # Inter-build clean, if the benchmark calls for it
            if (@targets > 1 && istrue($me->clean_between_builds)) {
                foreach my $target (@targets) {
                    my $targetflag = ($target ne '') ? " TARGET=$target" : '';
                    my $file = ($target ne '') ? "make.objclean.$target" : 'make.clean';
                    if (main::log_system("$make objclean$targetflag", $file, 0, [ $me, \%replacements ], 0)) {
                        $tmp = "Error with make objclean!\n";
                        Log(0, "  $tmp") if $rc;
                        $me->pop_ref;
                        $me->shift_ref;
                        $me->release($directory);
                        $me->compile_error_result('CE', $tmp);
                        return 1;
                    }
                }
            }

            # Do pre-build for each target
            if ($me->pre_build($directory->path(), 1, $target, undef)) {
                Log(0, "ERROR: pre-build setup failed for $target in ".$me->benchmark."\n");
                $me->shift_ref;
                $me->release($directory);
                $me->compile_error_result('CE', 'pre-build FAILED');
                return 1;
            }

	    my $targetflag = ($target ne '') ? " TARGET=$target" : '';
	    my $exe = ($target ne '') ? ".$target" : '';
	    $rc = main::log_system("$make build$targetflag", "make$exe", 0, [ $me, \%replacements], 0);
	    last if $rc;
	    if (!$rc || istrue($me->fake)) {
		$rc = main::log_system("$make options$targetflag", "options$exe", 0, [ $me, \%replacements ], 0);
		last if $rc;
                $compile_options .= read_compile_options("options${exe}.out", undef, 0);
	    }
	}

	if ($rc && !istrue($me->fake)) {
	    $tmp = "Error with make!\n";
	    Log(0, "  $tmp") if $rc;
	    $me->pop_ref;
	    $me->shift_ref;
	    $me->release($directory);
	    $me->compile_error_result('CE', $tmp);
            log_finish($bench, $compile_start);
	    return 1;
	}
    }

    main::monitor_shell('build_post_bench', $me);

    $me->pop_ref;
    $me->shift_ref;

    log_finish($bench, $compile_start);

    my @unmade = ();
    my $os_ext = $me->os_exe_ext;
    for my $name (@{$me->base_exe}) {
	if (! -x $name && ! -x "$name$os_ext") {
          my $tmpfname = ( -e $name ) ? $name : ( -e "$name$os_ext" ) ? "$name$os_ext" : "DOES NOT EXIST";
          Log(90, "$tmpfname exists, but ") if (-e $tmpfname);
          Log(90, "$tmpfname is not executable\n");
          Log(99, "stat for $tmpfname returns: ".join(', ', stat($tmpfname))."\n");
          push (@unmade, $name);
        }
    }
    if (@unmade && !istrue($me->fake)) {
	$tmp = "Some files did not appear to be built: ". join(', ',@unmade). "\n";
	Log(0, "  $tmp");
	$me->release($directory);
	$me->compile_error_result('CE', $tmp);
	return 1;
    }


    # Well we made it all the way here, so the executable(s) must be built
    # But are they executable? (Thank you, HP-UX.)
    # Copy them to the exe directory if they are.
    my $tune  = $me->smarttune;
    my $ext   = $me->ext;

    my $ctx = new Digest::MD5;
    my $head = jp($ownpath, $me->bindir, $subdir);
    if ( ! -d $head ) {
	eval { main::mkpath($head, 0, 0777) };
        if ($@) {
            $tmp .= "ERROR: Cannot create exe directory for ".$me->benchmark."\n";
            Log(0, $tmp);
            $me->release($directory);
            $me->compile_error_result('CE', $tmp);
            return 1;
        }
    }

    for my $name (sort { "${a}_$tune" cmp "${b}_$tune" } @{$me->base_exe}) {
        if (! -x $name && ! -x "$name$os_ext" && !istrue($me->fake)) {
          my $tmpfname = ( -e $name ) ? $name : ( -e "$name$os_ext" ) ? "$name$os_ext" : "DOES NOT EXIST";
          if (-e $tmpfname) {
            Log(5, "$tmpfname exists, but is not executable.  Skipping...\n"); 
          }
          next;
        }
	my $sname = $name;
	$sname .= $os_ext if ! -f $name && -f "$name$os_ext";
	if (!istrue($me->fake) &&
	    !main::copy_file($sname, "${name}_$tune.$ext", [$head], istrue($me->strict_rundir_verify))) {
	  Log(0, "ERROR: Copying executable from build dir to exe dir FAILED!\n");
	  $me->release($directory);
	  $me->compile_error_result('CE', $tmp);
	  return 1;
	}
	my $fh = new IO::File "<$sname";
	if (!defined $fh) {
	    Log(0, "Can't open file '$sname': $!\n") unless istrue($me->fake);
	} else {
            $ctx->addfile($fh);
        }
    }
    my $md5exe = $ctx->hexdigest;

    $md5ref->{'valid_build'} = $valid_build ? 'yes' : 'no';
    ($md5ref->{'rawcompile_options'}, undef, $md5ref->{'compile_options'}) = 
        main::compress_encode($compile_options);
    my $md5opt = $me->option_md5($compile_options);

    if ($md5ref->{'optmd5'} ne $md5opt) {
	$md5ref->{'optmd5'} = $md5opt;
	$md5ref->{'changedmd5'}++;
    }
    if ($md5ref->{'exemd5'} ne $md5exe) {
	$md5ref->{'exemd5'} = $md5exe;
	$md5ref->{'changedmd5'}++;
    }
    if ($md5ref->{'baggage'} ne $baggage) {
	$md5ref->{'changedmd5'}++;
    }

    # Do _not_ overwrite possibly good executable signatures when faking
    # a run.
    $md5ref->{'changedmd5'} = 0 if istrue($me->fake);

    $me->{'dirlist'} = [] unless (ref($me->{'dirlist'}) eq 'ARRAY');
    if ((istrue($me->minimize_rundirs) && ($directory->{'type'} eq 'run')) ||
	(istrue($me->minimize_builddirs) && ($directory->{'type'} eq 'build'))) {
	push @{$me->{'dirlist'}}, $directory;
    } else {
	$me->release($directory);
    }

    return 0;
}

sub log_finish {
    my ($bench, $compile_start) = @_;

    my $compile_finish = time;  ## used by the following log statement
    my $elapsed_time = $compile_finish - $compile_start;
    ::Log(160, "  Compile for '$bench' ended at: ".::ctime($compile_finish)." ($compile_finish)\n");
    ::Log(160, "  Elapsed compile for '$bench': ".::to_hms($elapsed_time)." ($elapsed_time)\n");
}

sub compile_error_result {
    my $me = shift @_;
    my $result = Spec::Config->new(undef, undef, undef, undef);

    $result->{'valid'}     = shift(@_);
    $result->{'errors'}    = [ @_ ];
    $result->{'tune'}      = $me->tune;
    $result->{'mach'}      = $me->mach;
    $result->{'ext'}       = $me->ext;
    $result->{'benchmark'} = $me->benchmark;
    if ($me->size_class eq 'ref') {
        $result->{'reference'} = $me->reference;
        $result->{'reference_power'} = $me->reference_power;
    } else {
        $result->{'reference'} = '--';
        $result->{'reference_power'} = '--';
    }

    $result->{'reported_sec'}  = '--';
    $result->{'reported_nsec'} = '--';
    $result->{'reported_time'} = '--';
    $result->{'ratio'}         = '--';
    $result->{'energy'}        = '--';
    $result->{'energy_ratio'}  = '--';
    $result->{'selected'}  = 0;
    $result->{'iteration'} = -1;
    $result->{'basepeak'}  = 0;
    $result->{'copies'}    = 1 if $::lcsuite =~ /cpu(?:2006|v6)/;
    $result->{'ranks'}     = 1 if $::lcsuite eq 'mpi2007';
    $result->{'threads'}   = 1 if ($::lcsuite =~ /^omp20(01|12)$/ || $::lcsuite eq 'cpuv6');
    $result->{'rate'}      = 0;
    $result->{'submit'}    = 0;
    if (istrue($me->power)) {
        $result->{'avg_power'} = 0;
        $result->{'min_power'} = 0;
        $result->{'max_power'} = 0;
        $result->{'max_uncertainty'} = -1;
        $result->{'avg_uncertainty'} = -1;
        $result->{'avg_temp'}  = 0;
        $result->{'min_temp'}  = 0;
        $result->{'max_temp'}  = 0;
        $result->{'avg_hum'}   = 0;
        $result->{'min_hum'}   = 0;
        $result->{'max_hum'}   = 0;
    }

    push (@{$me->{'result_list'}}, $result);

    # Remove the options read in from the MD5 section in the config file
    # (if any); they're not valid for this failed build.
    my $md5ref    = $me->config;
    for my $key ($me->benchmark, $me->smarttune, $me->ext, $me->mach) {
	if (!exists $md5ref->{$key} || ref($md5ref->{$key} ne 'HASH')) {
	    $md5ref->{$key} = {};
	}
	$md5ref = $md5ref->{$key};
    }
    delete $md5ref->{'compile_options'};
    delete $md5ref->{'rawcompile_options'};

    return $me;
}

sub link_rundirs {
    my ($me, $owner) = @_;
    $me->{'dirlist'} = $owner->{'dirlist'};
    $me->{'dirlist_is_copy'} = 1;
}

sub main::check_setup {
    # Given a list of log file lines, look to see whether a run directory
    # was created or re-used, and what its name was.
    my (@lines) = @_;

    foreach my $line (@lines) {
        if ($line =~ /: (created|existing) \((\S+)\)$/) {
            if ($1 eq 'created') {
                $::dirs_created = 1;
            }
            $::dirs_created{$2}++;
        }
    }
}

# This handles the spawning and cleanup of submit-type parallel setup jobs.
# It is substantially similar to run_parallel_tests in runspec
sub do_parallel_setup {
    my ($me, $concurrent, @dirs) = @_;

    my $top = $me->top;
    Log(200, "\n"); # Log file only
    my $config = $me->config;
    my $logdir = ::get_tmp_logdir($::global_config);
    if ( ! -d $logdir ) {
        # Something went wrong!
        Log(0, "WARNING: Temporary log directory \"$logdir\" couldn't be created\n");
        main::do_exit(1);
    }

    my @runspec_opts = ('--action', 'setup',
                        '--from_runspec', 2,
                        '--extension', $config->{'ext'},
                        '--machine', $config->{'mach'},
                        '--size', $config->{'size'},
                        '--nobuild',
                        '--noreportable',
                        '--noignore-errors',
                        '--verbose', $config->verbose,
                        );

    %::children = ();
    $::running = 0;
    $::child_loglevel = 110;
    $::dirs_created = 0;
    %::dirs_created = ();
    my $start_time;
    my @command = ();
    my $command = '';
    for(my $i = 0; $i < @dirs; $i++) {
        my $dir = $dirs[$i];
        next unless defined($dir) && (::reftype($dir) eq 'HASH');
        my $pid = undef;
        if ($::running < $concurrent) {
            my $logfile = jp($logdir, $me->num.'.'.$me->name.'.'.$config->{'size'}.'.'.$me->tune.'.'.$i);
            my $lognum = $::global_config->{'lognum'}.'.'.$i;
            my $tmpdir = ::get_tmp_directory($me, 1, 'setup.'.$me->num.'.'.$me->name.'.'.$config->{'size'}.'.'.$me->tune.$i);
            if ( ! -d $tmpdir ) {
                # Something went wrong!
                Log(0, "ERROR: Temporary directory \"$tmpdir\" couldn't be created\n");
                next;
            }
            chdir($tmpdir);

            # Put the command together now so it can be logged in the main
            # log file.
            @command = ::generate_runspec_commandline($::cl_opts, $config,
                                                      $::cl_pp_macros,
                                                      $::cl_opts->{'pp_unmacros'},
                                                      @runspec_opts,
                                                      '--copynum', $i,
                                                      '--tune', $me->tune,
                                                      '--logfile', $logfile,
                                                      '--lognum', $lognum,
                                                      '--userundir', $dir->path,
                                                      $me->num.'.'.$me->name);
	    my %submit = $me->assemble_submit();
	    my $submit = exists($submit{'runspec'}) ? $submit{'runspec'} : $submit{'default'};
	    $submit = '$command' if $submit eq '';
	    $me->unshift_ref({ 'command' => '' });
	    $me->command(join(' ', @command));
	    $command = ::command_expand($submit, $me);
            $me->shift_ref();
	    my $bindval = $me->bind;
	    my @bindopts = (reftype($bindval) eq 'ARRAY') ? @{$bindval} : ();
	    if (defined($bindval) && @bindopts) {
		$bindval = $bindopts[$i % ($#bindopts + 1)];
		$command =~ s/\$BIND/$bindval/g;
	    }
	    $command =~ s/\$SPECCOPYNUM/$i/g;
            Log(110, "\nAbout to exec \"$command\" for setup of ".$me->descmode('no_threads' => 1)."\n");

            ($start_time, $pid) = ::runspec_fork($me, \%::children, $i,
                                                 'loglevel' => 10,
                                                 'parent_msg' => "  Started child (\$pid) to setup copy $i for ".$me->descmode('no_threads' => 1)."\n",
                                                 'child_msg' => "  Setting up copy $i for ".$me->descmode('no_threads' => 1)."\n",
                                                 'log' => 1,
                                                );
            if ($pid) {
                chdir($top);
                $::children{$pid}->{'logfile'} = $logfile;
                $::children{$pid}->{'bench'} = $me;
                $::children{$pid}->{'log_proc'} = \&main::check_setup;
                $::children{$pid}->{'tmpdir'} = $tmpdir;
                next;
            }
        } else {
            # Wait a bit for kids to exit
            Time::HiRes::sleep 0.3;
            ::check_children('Setup');
            redo;        # Try again
        }

        # In child process here
        exec $command;
        Log(0, "ERROR: exec of runspec failed: $!\n");
        main::do_exit(1);
    }
#    if ($::running) {
#        Log(3, "Waiting for running setup processes to finish...\n");
#    }
#    Log(3, "\n");
    while ($::running > 0) {
      ::check_children('Setup');
      Time::HiRes::sleep 0.3;
    }
    ::check_children('Setup');   # Just in case

    if ($me->post_setup(map { $_->path } @dirs)) {
      Log(0, "ERROR: post_setup for " . $me->benchmark . " failed!\n");
      return(undef);
    };

    $me->{'dirlist'} = [ @dirs ];

    return ($::dirs_created, sort keys %::dirs_created);
}

sub is_parallel_setup {
    my ($me, $numdirs) = @_;

    return 0 if $::from_runspec;

    my $concurrent = $me->parallel_setup || 1;
    $concurrent = 1 unless ($numdirs > 1);  # Don't fork unnecessarily
    my $setup_type = lc($me->parallel_setup_type);

    if ($concurrent > 1 && $setup_type !~ /^(fork|submit|none)$/) {
        $concurrent = 1;
    }

    return $concurrent > 1;
}

sub setup_rundirs {
    my ($me, $numdirs, $path) = @_;
    my $rc;
    my $tune  = $me->smarttune;
    my $ext   = $me->ext;
    my $mach   = $me->mach;
    my $size   = $me->size;
    my $nodel  = exists($ENV{"SPEC_${main::suite}_NO_RUNDIR_DEL"}) ? 1 : 0;
    my $concurrent = $me->parallel_setup || 1;
    $concurrent = 1 unless ($numdirs > 1);  # Don't fork unnecessarily
    my $bind = $me->parallel_setup_prefork;
    my $setup_type = lc($me->parallel_setup_type);
    my @dirs;
    if (defined($path) && $path ne '' && $::from_runspec == 2) {
        # This is a child of a submit-type parallel setup; only do one
        # dir, and be serial about it.
        @dirs = $me->reserve($nodel, 1, 'dir' => $path);
        $setup_type = 'none';
        $concurrent = 1;
    } else {
        # The usual thing -- get some run dirs
        @dirs = $me->reserve($nodel, $numdirs,
                             'type'=>'run', 'tune'=>$tune, 'ext' => $ext,
                             'mach' => $mach, 'size'=>$size,
                             'username' => $me->username);
    }
    if (!@dirs) {
       Log(0, "\nERROR: Could not reserve run directories!\n");
       return undef;
    }

    if ($concurrent > 1 && $setup_type !~ /^(fork|submit|none)$/) {
        Log(0, "ERROR: Parallel setup specified, but setup type must be one of 'fork',\n        'submit', or 'none'.\n");
        Log(0, "       Disabling parallel setup.\n");
        $concurrent = 1;
        $setup_type = 'none';
    } elsif ($setup_type eq 'none') {
        $concurrent = 1;
    } elsif ($^O =~ /MSWin/) {
        # Parallel setup doesn't work on Windows
        $concurrent = 1;
        $setup_type = 'none';
    } elsif ($concurrent > 1 && $setup_type eq 'submit') {
        return $me->do_parallel_setup($concurrent, @dirs);
    }

    my $head = jp($me->path, $me->datadir);
    my @work_dirs = $me->workload_dirs($head, $size, $me->inputdir);

    # Quick check for "bad" directories
    for my $dir (@dirs) {
        # CVT2DEV: $dir->{'bad'} = 1;    # No sums, so always re-copy
	# They're bad if we say they are
	if (istrue($me->deletework)) {
	    $dir->{'bad'} = 1;
	}
	# Any directories that don't exist are obviously bad
	if (!-d $dir->path) {
	    eval { main::mkpath($dir->path) };
            if ($@) {
                Log(0, "ERROR: Cannot create run directory for ".$me->benchmark.": $@\n");
                return(undef);
            }
	    $dir->{'bad'} = 1;
	}
    }

    # Check to see which directories are ok
    my $fast = !istrue($me->strict_rundir_verify) || istrue($me->fake);
    # CVT2DEV: $fast = 1;
    my @input_files = $me->input_files_abs($me->size, 1);
    if (@input_files+0 == 0 ||
	!defined($input_files[0])) {
	Log(0, "Error during setup for ".$me->benchmark.": No input files!?\n");
	return(undef);
    }

    # This _only_ checks to see whether files are okay or not.  This is done
    # by the main runspec process even if concurrent setup is selected because
    # This only processes the reference input files, and because the data
    # structure it might fix up needs to be available to all children.
    # Otherwise each child would end up recalculating MD5s that should only
    # be done once.
    for my $reffile (@input_files) {
	next if istrue($me->fake);
	# We can't just do basename here, because sometimes there are files
	# in subdirs
	my $refsize  = stat($reffile)->size;
        my $isbz2 = 0;
        $isbz2 = 1 if ($reffile =~ s/\.bz2$//);
	my $short    = $reffile;
	my $refdigest = $::file_md5{$reffile};
	foreach my $wdir (@work_dirs) {
     	     $short       =~ s%^($wdir)/%%i;
        }
        if (!$isbz2) {
	    if (!$fast && $refdigest eq '') {
		$refdigest = main::md5filedigest($reffile);
		$::file_md5{$reffile} = $refdigest;
	    }
        } else {
	    if (exists($::file_md5{$reffile})) {
		$refdigest = $::file_md5{$reffile};
	    }
	    if (exists($::file_size{$reffile}) && $refdigest ne '') {
		$refsize = $::file_size{$reffile};
	    } else {
		# Uncompress the file
		# This should not happen, because the MD5 of the uncompressed
		# file should be in SUMS.data.
		Log(10, "MD5 hash of ${reffile} being generated.  SUMS.data be damaged or incomplete.\n");
		my $bz = new IO::Uncompress::Bunzip2 "${reffile}.bz2", Buffer => 262144;
		if (defined($bz)) {
		    my $tmp = '';
		    my ($size, $sum) = (0, undef);
		    my $md5 = new Digest::MD5;
                    my $status;
		    while (($status = $bz->read($tmp)) > 0) {
			$size += length($tmp);
			$md5->add($tmp);
		    }
		    $size += length($tmp);
		    $md5->add($tmp);
                    $bz->close();
		    if ($status >= 0) {
			# Since the decompression takes by far the longest time,
			# the MD5 hash will be calculated for later use even if
			# $fast is set.
			$::file_size{$reffile} = $refsize = $size;
			$::file_md5{$reffile} = $refdigest = $md5->hexdigest if ($refdigest eq '');
		    }
		}
	    }
	}
    }

    %::children = ();
    $::running = 0;
    $::child_loglevel = 10;
    my $start_time;
    for(my $i = 0; $i < @dirs; $i++) {
        my $dir = $dirs[$i];
	next if $dir->{'bad'} || istrue($me->fake);
	$dir->{'bad'} = 0;   # Just so it's defined
        my $pid = undef;
        if ($concurrent > 1 && @dirs > 1) {
	    if ($::running < $concurrent) {
		($start_time, $pid) = ::runspec_fork($me, \%::children, $i,
                                                     'loglevel' => $::child_loglevel,
                                                     'bind' => $bind,
                                                     'parent_msg' => "Started child (\$pid) to check run directory for copy \$idx\n",
                                                     'child_msg' => "Checking run directory for copy \$idx: ".File::Basename::basename($dirs[$i]->path)."\n",
                                                     'log' => 1,
                                                     'error_exits_ok' => [ 1 ],
                                                    );
                if ($pid) {
                    $::children{$pid}->{'bench'} = $me;
                    next;
                }
	    } else {
	        # Wait a bit for kids to exit
                Time::HiRes::sleep 0.3;
                ::check_children('Setup');
		redo;	# Try again
	    }
	}
	for my $reffile (@input_files) {
	    my $refsize;
	    my $isbz2 = 0;
	    $reffile =~ s/\.bz2$//;
	    my $short    = $reffile;
	    my $refdigest = $::file_md5{$reffile};
	    foreach my $wdir (@work_dirs) {
     	       $short       =~ s%^($wdir)/%%i;
            }
	    if (exists($::file_size{$reffile}) && $refdigest ne '') {
		$refsize = $::file_size{$reffile};
	    } else {
		$refsize  = stat($reffile);
		$refsize = $refsize->size if (defined($refsize));
	    }
	    my $target = jp($dir->path, $short);
            if (!-f $target) {
		Log($::child_loglevel, "$short not found in run dir ".$dir->path."; marking as bad.\n");
		$dir->{'bad'} = 1;
	    } elsif (-s $target != $refsize) {
		Log($::child_loglevel, "Size of $short does not match reference; marking rundir as bad.\n");
		$dir->{'bad'} = 1;
	    } elsif (!$fast) {
		if ($concurrent <= 1) {
		    # This is too much pollution in the log for concurrent runs
		    if (istrue($me->strict_rundir_verify)) {
			Log($::child_loglevel, "Doing REALLY slow MD5 tests for $target\n");
		    } else {
			Log($::child_loglevel, "Doing slow MD5 tests for $target\n");
		    }
		}
                my $shortmd5 = main::md5filedigest($target);
                if ($refdigest ne $shortmd5) {
                    Log($::child_loglevel, "MD5 sum of $short does not match cached sum of reference file; rundir is bad.\n");
                    $dir->{'bad'} = 1;
                } elsif (istrue($me->strict_rundir_verify) &&
                         main::md5filedigest($reffile) ne $shortmd5) {
                    Log($::child_loglevel, "MD5 sum of $short does not match reference; marking rundir as bad.\n");
                    $dir->{'bad'} = 1;
                }
            }
	}
        if ($concurrent > 1 && $pid == 0) {
	    Log($::child_loglevel, sprintf("Finished run directory check for copy $i in %.3fs\n", Time::HiRes::time - $start_time));
	    main::close_log();
	    # Exit with non-zero rc if the directory is bad
	    exit($dir->{'bad'} ? 1 : 0);
	}
    }

    if ($concurrent > 1) {
	# Wait for children
	while($::running > 0) {
            ::check_children('Setup');
            Time::HiRes::sleep 0.3;
	}
        ::check_children('Setup');      # Just in case
	foreach my $kidpid (keys %::children) {
	    my $idx = $::children{$kidpid}->{'idx'};
	    if (defined($idx)) {
		if ($::children{$kidpid}->{'rc'} > 1) {
		    Log(0, "ERROR: Execution error for setup:check of copy $idx\n");
                    return(undef);
		}
		$dirs[$idx]->{'bad'} = $::children{$kidpid}->{'rc'};
	    } else {
	    	Log(0, "ERROR: No directory index for setup:check child PID $kidpid\n");
		return(undef);
	    }
	}
    }

    # Remove output and other files from directories which are ok.
    # This is also serial, because the only I/O that it'll do is reading
    # directories and removing files.  
    for my $dir (@dirs) {
	next if $dir->{'bad'};
	my $basepath = $dir->path;
	$dir->{'bad'} = $me->clean_single_rundir($basepath);
	my $dh = new IO::Dir $dir->path;
	if (!defined $dh) {
	    $dir->{'bad'} = 1;
	    next;
	}
	# This should never have anything to do.
	while (defined(my $file = $dh->read)) { 
	    next if ($file !~ m/\.(out|err|cmp|mis)$/);
	    my $target = jp($dir->path, $file);
	    if (!unlink ($target)) {
		$dir->{'bad'} = 1;
		last;
	    }
	}
    }

    my $needed_setup = 0;
    my @dirnum = ();
    # Now rebuild all directories which are not okay
    my @copy_dirs = ();
    for my $dir (@dirs) {
	my $path = $dir->path();
	push @dirnum, File::Basename::basename($path);

	if ($dir->{'bad'}) {
            $needed_setup = 1;
            delete $dir->{'bad'};
            if (!::rmpath($path)) {
                eval { main::mkpath($path) };
                if ($@) {
                    Log(0, "ERROR: Cannot create run directory for ".$me->benchmark.": $@\n");
                    return(undef);
                }
            }
            push @copy_dirs, $path;
        } else {
            push @copy_dirs, undef;
        }

    }

    # Copy input files to dirs that need them
    if (grep { defined } @copy_dirs) {
        # copy_input_files_to knows how to be parallel itself
	if ($me->copy_input_files_to($fast, $me->size, $concurrent, $bind, @copy_dirs)) {
	    Log(0, "ERROR: Copying input files to run directory FAILED\n");
	    return(undef);
	}
    }

    # Copy executables to first directory
    if (!istrue($me->fake) && ($::from_runspec != 2 || $::cl_opts->{'copynum'} == 0)) {
	for my $file ($me->exe_files_abs) {
	  if (!main::copy_file($file, undef, [$dirs[0]->path], istrue($me->strict_rundir_verify))) {
	    Log(0, "ERROR: Copying executable to run directory FAILED\n");
	    return(undef);
	  }
	}
    }

    if ($::from_runspec != 2) {
        # Don't do this for submit-based parallel setup; do_parallel_setup
        # will handle it.
        if ($me->post_setup(map { $_->path } @dirs)) {
          Log(0, "ERROR: post_setup for " . $me->benchmark . " failed!\n");
          return(undef);
        }
    }

    $me->{'dirlist'} = [ @dirs ];

    return ($needed_setup, @dirnum);
}

# This handles the spawning and cleanup of submit-type parallel cleanup jobs.
# It is substantially similar to do_parallel_setup
sub do_parallel_cleanup {
    my ($me, $concurrent, @dirs) = @_;

    my $top = $me->top;
    my $rc = 0;
    my $config = $me->config;
    my $logdir = ::get_tmp_logdir($::global_config);
    if ( ! -d $logdir ) {
        # Something went wrong!
        Log(0, "WARNING: Temporary log directory \"$logdir\" couldn't be created\n");
        main::do_exit(1);
    }
    my @runspec_opts = ('--action', 'interclean',
                        '--from_runspec', 3,
                        '--extension', $config->{'ext'},
                        '--machine', $config->{'mach'},
                        '--size', $config->{'size'},
                        '--nobuild',
                        '--noreportable',
                        '--noignore-errors',
                        '--verbose', $config->verbose,
                        );

    %::children = ();
    $::running = 0;
    $::child_loglevel = 110;
    $::dirs_created = 0;
    %::dirs_created = ();
    my $start_time;
    my @command = ();
    my $command = '';
    for(my $i = 0; $i < @dirs; $i++) {
        my $dir = $dirs[$i];
        next unless defined($dir) && (::reftype($dir) eq 'HASH');
        my $pid = undef;
        if ($::running < $concurrent) {
            my $logfile = jp($logdir, $me->num.'.'.$me->name.'.'.$config->{'size'}.'.'.$me->tune.'.'."clean$i");
            my $lognum = $::global_config->{'lognum'}.'.'.$i;
            @command = ::generate_runspec_commandline($::cl_opts, $config,
                                                      $::cl_pp_macros,
                                                      $::cl_opts->{'pp_unmacros'},
                                                      @runspec_opts,
                                                      '--copynum', $i,
                                                      '--tune', $me->tune,
                                                      '--logfile', $logfile,
                                                      '--lognum', $lognum,
                                                      '--userundir', $dir->path,
                                                      $me->num.'.'.$me->name);
            my $tmpdir = ::get_tmp_directory($me, 1, 'interclean.'.$me->num.'.'.$me->name.'.'.$config->{'size'}.'.'.$me->tune.$i);
            if ( ! -d $tmpdir ) {
                # Something went wrong!
                Log(0, "ERROR: Temporary directory \"$tmpdir\" couldn't be created\n");
                next;
            }
            chdir($tmpdir);

            # Assemble the command here so that it can be logged in the main
            # log file.
	    my %submit = $me->assemble_submit();
	    my $submit = exists($submit{'runspec'}) ? $submit{'runspec'} : $submit{'default'};
	    $submit = '$command' if $submit eq '';
	    $me->unshift_ref({ 'command' => '' });
	    $me->command(join(' ', @command));
	    $command = ::command_expand($submit, $me);
	    my $bindval = $me->bind;
            $me->shift_ref();
	    my @bindopts = (reftype($bindval) eq 'ARRAY') ? @{$bindval} : ();
	    if (defined($bindval) && @bindopts) {
		$bindval = $bindopts[$i % ($#bindopts + 1)];
		$command =~ s/\$BIND/$bindval/g;
	    }
	    $command =~ s/\$SPECCOPYNUM/$i/g;
            Log(110, "\nAbout to exec \"$command\"\n");

            ($start_time, $pid) = ::runspec_fork($me, \%::children, $i,
                                                 'loglevel' => 10,
                                                 'parent_msg' => "  Started child (\$pid) for inter-run cleanup of copy $i for ".$me->descmode('no_threads' => 1)."\n",
                                                 'child_msg' => "  Doing inter-run cleanup of copy $i for ".$me->descmode('no_threads' => 1)."\n",
                                                 'log' => 1,
                                                );
            if ($pid) {
                chdir($top);
                $::children{$pid}->{'logfile'} = $logfile;
                $::children{$pid}->{'bench'} = $me;
                $::children{$pid}->{'tmpdir'} = $tmpdir;
                next;
            }
        } else {
            # Wait a bit for kids to exit
            Time::HiRes::sleep 0.3;
            $rc |= ::check_children('Inter-run cleanup');
            redo;        # Try again
        }

        # In child process here
        exec $command;
        Log(0, "ERROR: exec of runspec failed: $!\n");
        main::do_exit(1);
    }
#    if ($::running) {
#        Log(3, "Waiting for running inter-run cleanup processes to finish...\n");
#    }
#    Log(3, "\n");
    while ($::running) {
      $rc |= ::check_children('Inter-run cleanup');
      Time::HiRes::sleep 0.3;
    }
    $rc |= ::check_children('Inter-run cleanup');   # Just in case

    return $rc;
}

# The starting point for all run directory cleanup.
# For submit-type parallel cleanup, just hands off to do_parallel_cleanup.
# Handles bind-type parallel and serial cleanup itself.
sub cleanup_rundirs {
  my ($me, $numdirs, $path) = (@_);
  my $rc = 0;

  return 0 if istrue($me->fake);

  $numdirs = @{$me->{'dirlist'}}+0 if ($numdirs <= 0);

  my $concurrent = $me->parallel_setup || 1;
  $concurrent = 1 unless ($numdirs > 1);  # Don't fork unnecessarily
  my $bind = $me->parallel_setup_prefork;
  my $setup_type = lc($me->parallel_setup_type);

  if (defined($path) && $path ne '' && $::from_runspec == 3) {
      # This is a child of a submit-type parallel cleanup; only do one dir
      $me->{'dirlist'} = [ $me->reserve(0, 1, 'dir' => $path) ];
      $setup_type = 'none';
      $concurrent = 1;
      $numdirs = 1;
  }

  if ($concurrent > 1 && $setup_type !~ /^(fork|submit|none)$/) {
      Log(0, "ERROR: Parallel setup specified, but setup type must be one of 'fork',\n        'submit', or 'none'.\n");
      Log(0, "       Disabling parallel setup.\n");
      $concurrent = 1;
      $setup_type = 'none';
  } elsif ($setup_type eq 'none') {
      $concurrent = 1;
  } elsif ($^O =~ /MSWin/) {
      $concurrent = 1;
      $setup_type = 'none';
  } elsif ($concurrent > 1 && $setup_type eq 'submit') {
      return $me->do_parallel_cleanup($concurrent, @{$me->{'dirlist'}});
  }

  %::children = ();
  $::running = 0;
  $::child_loglevel = 10;
  my $start_time;
  for (my $i = 0; $i < $numdirs; $i++) {
    my $dir = $me->{'dirlist'}[$i]->path;
    my $pid = undef;
    if ($concurrent > 1 && $numdirs > 1) {
        if ($::running < $concurrent) {
            ($start_time, $pid) = ::runspec_fork($me, \%::children, $i,
                                                 'loglevel' => $::child_loglevel,
                                                 'bind' => $bind,
                                                 'parent_msg' => "Started child (\$pid) to clean run directory for copy \$idx\n",
                                                 'child_msg' => "Cleaning run directory for copy \$idx: ".File::Basename::basename($dir)."\n",
                                                 'log' => 1
                                                );
            if ($pid) {
                $::children{$pid}->{'bench'} = $me;
                next;
            }
        } else {
            # Wait a bit for kids to exit
            Time::HiRes::sleep 0.3;
            $rc |= ::check_children('Cleanup');
            redo;	# Try again
        }
    }
    my @fh_list = ();
    for my $file ($me->exe_files_abs) {
      my $fullpath = jp($dir, basename($file));
      if (-e $fullpath) {
	# Make an effort to make the executable be less-easily identifiable
	# as the _same_ executable that we used last time.
	rename $fullpath, "${fullpath}.used.$$";
	my $ofh = new IO::File ">${fullpath}.used.$$";
	$ofh->print("#!/bin/sh\necho This is a non-functional placeholder\n");
	# Make sure that we maintain an open filehandle to the placeholder,
	# so that when the file is unlinked its inode doesn't get reallocated.
        push @fh_list, $ofh;
	# clean_single_rundir will take care of the placeholder file for us
	if (!main::copy_file($file, undef, [$dir], 1)) {
	  Log(0, "ERROR: Copying executable to run directory FAILED in cleanup_rundirs\n");
          if ($concurrent > 1 && $pid == 0) {
              exit 255;
          } else {
              return 1;
          }
	}
      }
    }
    # All the files are copied now, so go ahead and kill the temps
    my $fh = shift @fh_list;
    while(defined($fh) && ref($fh) eq 'IO::File') {
        $fh->close();
        $fh = shift @fh_list;
    }
    $rc |= $me->clean_single_rundir($dir);
    if ($concurrent > 1 && $pid == 0) {
        Log($::child_loglevel, sprintf("Finished run directory cleanup for copy $i in %.3fs (rc=$rc)\n", Time::HiRes::time - $start_time));
        main::close_log();
        exit($rc);
    }
  }
#  if ($::running) {
#    Log(3, "Waiting for running cleanup processes to finish...\n");
#  }
#  Log(3, "\n");
  while ($::running) {
    $rc |= ::check_children('Cleanup');
    Time::HiRes::sleep 0.3;
  }
  $rc |= ::check_children('Cleanup');   # Just in case

  return $rc;
}

sub clean_single_rundir {
  my ($me, $basepath) = @_;
  my $head = jp($me->path, $me->datadir);
  my @work_dirs = $me->workload_dirs($head, $me->size, $me->inputdir);
  my @tmpdir = ($basepath);
  my @files = ();

  while (defined(my $curdir = shift(@tmpdir))) {
    my $dh = new IO::Dir $curdir;
    next unless defined $dh;
    foreach my $file ($dh->read) {
      next if ($file eq '.' || $file eq '..');
      $file = jp($curdir, $file);
      if ( -d $file ) {
	push @tmpdir, $file;
      } else {
	push @files, $file;
      }
    }
  }
  # Strip the top path from the list of files we just discovered
  @files = sort map { s%^$basepath/%%i; jp(dirname($_), basename($_, '.bz2')) } @files;

  # Make a list of the files that are allowed to be in a run directory
  # before a run starts.  This could be (and was) done as a much more
  # concise and confusing one-liner using map.  Hey, not everyone has
  # 1337 p3r1 skillz.
  my %okfiles = ();
  foreach my $okfile ($me->exe_files,
		      $me->input_files_base,
		      $me->added_files_base) {
    foreach my $wdir (@work_dirs) {
       $okfile =~ s%^($wdir)/%%i;
    }
    $okfiles{jp(dirname($okfile), basename($okfile, '.bz2'))}++;
  }

  # The "everything not mandatory is forbidden" enforcement section
  for my $reffile (@files) {
    next if exists($okfiles{$reffile});
    my $target = jp($basepath, $reffile);
    next if !-f $target;
    if (!unlink($target)) {
        Log(0, "\nERROR: Failed to unlink $target\n");
        return 1;
    }
  }

  return 0;
}

sub delete_binaries {
    my ($me, $all) = @_;
    my $path = $me->path;
    if ($me->output_root ne '') {
      my $oldtop = ::make_path_re($me->top);
      my $newtop = $me->output_root;
      $path =~ s/^$oldtop/$newtop/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';

    my $head = jp($path, $me->bindir, $subdir);
    if ($all) {
	::rmpath($head);
    } else {
	my $tune  = $me->smarttune;
	my $ext   = $me->ext;
# Why are we leaving mach out of the filenames again?  I can't remember...
#	my $mach  = $me->mach;
#	if ($mach eq 'default') {
#	    $mach = '';
#	} elsif ($mach ne '') {
#	    $mach = "_$mach";
#	}
	for my $name (@{$me->base_exe}) {
#	    unlink(jp($head, "${name}_$tune$mach.$ext"));
	    unlink(jp($head, "${name}_$tune.$ext"));
	}
    }
}

sub delete_rundirs {
    my ($me, $all) = @_;
    my $path = $me->{'path'};
    my $top = $me->top;
    if ($me->output_root ne '') {
      my $oldtop = ::make_path_re($top);
      $top = $me->output_root;
      $path =~ s/^$oldtop/$top/;
    }
    my $subdir = $me->expid;
    $subdir = undef if $subdir eq '';

    my @attributes = ();

    if ($all) {
	my $dir = jp($path, $::global_config->{'rundir'}, $subdir);
	::rmpath($dir);
	$dir = jp($path, $::global_config->{'builddir'}, $subdir);
	::rmpath($dir);
    } else {
	@attributes = ([
	    'username'=>$me->username, 'size'=>$me->size, 'ext'=>$me->ext,
	    'tune'=>$me->smarttune, 'mach'=>$me->mach,
	], [
	    'username'=>$me->username, 'type'=>'build', 'ext'=>$me->ext,
	]);

        foreach my $type (qw(build run)) {
            my $file = $me->lock_listfile($type);
            my $entry;
            for my $attr (@attributes) {
                while (1) {
                    $entry = $file->find_entry($top, @$attr);
                    last if !$entry;
                    ::rmpath($entry->path);
                    rmdir($entry->path);
                    $entry->remove();
                }
            }
            $file->update();
            $file->close();
        }
    }
}

sub remove_rundirs {
    my ($me) = @_;

    if ($me->{'dirlist_is_copy'}) {
	delete $me->{'dirlist_is_copy'};
    } else {
	if (ref($me->{'dirlist'}) eq 'ARRAY') {
	    my @dirs = @{$me->{'dirlist'}};
	    for my $dirobj (@dirs) {
		::rmpath($dirobj->path);
	    }
	    $me->release(@dirs);
	} else {
	    Log(3, "No list of directories to remove for ".$me->descmode('no_threads' => 1)."\n");
	}
    }
    $me->{'dirlist'} = [];
}

sub release_rundirs {
    my ($me) = @_;

    if ($me->{'dirlist_is_copy'}) {
	delete $me->{'dirlist_is_copy'};
    } elsif (ref($me->{'dirlist'}) eq 'ARRAY') {
	my @dirs = @{$me->{'dirlist'}};
	$me->release(@dirs);
    }
    $me->{'dirlist'} = [] unless (istrue($me->minimize_rundirs));
}

sub reserve {
    my ($me, $nodel, $num, %attributes) = @_;
    my $top = $me->top;
    if ($me->output_root ne '') {
      $top = $me->output_root;
    }

    $num = 1 if ($num eq '');
    if (keys %attributes == 0) {
	%attributes = ( 'username' => $me->username,  'ext'  => $me->ext,
			'tune'     => $me->smarttune, 'mach' => $me->mach );
    }
    # If we're looking for a particular PATH, then we want it to be locked.
    # Otherwise, it should be unlocked.
    if (exists($attributes{'dir'}) && $attributes{'dir'} ne '') {
        $attributes{'lock'} = 1;
    } else {
        $attributes{'lock'} = 0;
    }
    my $name;
    my %temp;
    foreach my $thing (qw(type tune size ext)) {
        ($temp{$thing} = $attributes{$thing}) =~ tr/-A-Za-z0-9./_/cs;
    }
    if ($attributes{'type'} eq 'run') {
        $name = sprintf("%s_%s_%s_%s", $temp{'type'}, $temp{'tune'},
                                       $temp{'size'}, $temp{'ext'});
    } elsif ($attributes{'type'} eq 'build') {
        $name = sprintf("%s_%s_%s", $temp{'type'}, $temp{'tune'}, $temp{'ext'});
    } else {
        if ($attributes{'type'} eq '') {
            $attributes{'type'} = 'unknown';
        }
        $name = sprintf("UNKNOWN_%s_%s_%s", $temp{'tune'}, $temp{'size'},
                                            $temp{'ext'});
    }

    my $file = $me->lock_listfile($attributes{'type'});
    my @entries;

    for (my $i = 0; $i < $num; $i++ ) {
	my $entry = $file->find_entry($top, %attributes);
	if (!$entry || $nodel) {
            $attributes{'lock'} = 0;
	    $entry = $file->new_entry($name, 'username' => $me->username, %attributes);
	}
	push @entries, $entry;
	$entry->lock($me->username);
    }
    $file->update();
    $file->close();
    push @{$me->{'entries'}}, @entries;

    return @entries;
}

sub release {
    my ($me, @dirs) = @_;

    my %dirs = (
                'build' => [ grep { $_->{'type'} eq 'build' } @dirs ],
                'run'   => [ grep { $_->{'type'} ne 'build' } @dirs ],
               );

    foreach my $type (qw(build run)) {
        next unless @{$dirs{$type}};
        my $file = $me->lock_listfile($type);
        for my $dir (@{$dirs{$type}}) {
            my $entry = $file->find_entry_name($dir->name);
            if ($entry) {
                $entry->unlock($dir->name);
            } else {
                Log(0, "WARNING: release: Bogus entry in $type entries list\n");
            }
        }
        $file->update();
        $file->close();
    }
}

sub was_submit_used {
    # Determine whether submit was used
    my ($me, $is_training) = @_;

    # For the purposes of this determination, it's sufficient for _any_
    # submit (other than runspec) to be set.
    my %submit = $me->assemble_submit();
    delete $submit{'runspec'};
    my $submit = join("\n", map { $submit{$_} } keys %submit);
    
    # This conditional matches what's in run_benchmark()
    if ($submit ne ''
        &&
        # Submit should only be used for training runs when plain_train is
        # unset and use_submit_for_speed is set.
        (!$is_training ||
          (!istrue($me->plain_train) &&
           istrue($me->use_submit_for_speed))
        )
        &&
        (istrue($me->rate) ||
         istrue($me->shrate) ||
         istrue($me->use_submit_for_speed))) {
      return 1;
    } else {
      return 0;
    }
}

sub make_empty_result {
    my ($me, $num_copies, $iter, $add_to_list, $is_training) = @_;

    my $result = Spec::Config->new();
    $result->{'valid'}         = 'S';
    $result->{'errors'}        = [];
    $result->{'tune'}          = $me->tune;
    $result->{'mach'}          = $me->mach;
    $result->{'ext'}           = $me->ext;
    $result->{'selected'}      = 0;
    $result->{'rate'}          = istrue($me->rate);
    $result->{'benchmark'}     = $me->benchmark;
    $result->{'basepeak'}      = 0;
    $result->{'iteration'}     = $iter;
    $result->{'clcopies'}      = $num_copies if $::lcsuite =~ /cpu(?:2006|v6)/;
    $result->{'ranks'}         = $me->ranks if $::lcsuite eq 'mpi2007';
    $result->{'threads'}       = $me->ranks if ($::lcsuite =~ /^omp20(01|12)$/ || $::lcsuite eq 'cpuv6');
    $result->{'submit'}        = was_submit_used($me, $is_training);
    $result->{'rc'}            = 0;
    $result->{'reported_sec'}  = 0;
    $result->{'reported_nsec'} = 0;
    $result->{'reported_time'} = 0;
    $result->{'selected'}      = 0;
    $result->{'dp'}            = -1;
    if ($me->size_class eq 'ref' && !$is_training) {
        $result->{'ratio'}           = 0;
        $result->{'energy_ratio'}    = 0 if istrue($me->power);
        $result->{'reference'}       = $me->reference;
        $result->{'reference_power'} = $me->reference_power;
    } else {
        $result->{'ratio'}           = '--';
        $result->{'energy_ratio'}    = '--' if istrue($me->power);
        $result->{'reference'}       = '--';
        $result->{'reference_power'} = '--';
    }
    if (istrue($me->power)) {
        $result->{'energy'}    = 0;
        $result->{'avg_power'} = 0;
        $result->{'min_power'} = 0;
        $result->{'max_power'} = 0;
        $result->{'max_uncertainty'} = -1;
        $result->{'avg_uncertainty'} = -1;
        $result->{'avg_temp'}  = 0;
        $result->{'min_temp'}  = 0;
        $result->{'max_temp'}  = 0;
        $result->{'avg_hum'}   = 0;
        $result->{'min_hum'}   = 0;
        $result->{'max_hum'}   = 0;
    }
    return undef if $result->{'reference'} == 1;

    if (defined($add_to_list)) {
        push @{$me->{'result_list'}}, $result;
    }

    return $result;
}

sub assemble_submit {
    # Assemble a hash (keyed by executable name) of submit commands.
    # Ones that were multiply-valued will be joined into a single string.
    my ($me) = @_;
    my %submit = ();
    
    foreach my $line (grep { /^submit_\S+\d*$/ } $me->list_keys) {
      my ($exe, $idx) = $line =~ m/^submit_(\S+)(\d*)$/;
      my $val = $me->accessor($line);
      $submit{$exe}->[$idx] = $val;
    }

    # Now do the "generic" one
    foreach my $line (grep { /^submit\d*$/ } $me->list_keys) {
      my ($idx) = $line =~ m/^submit(\d*)$/;
      my $val = $me->accessor($line);
      $submit{'default'}->[$idx] = $val;
    }

    foreach my $exe (sort keys %submit) {
      # The linefeeds will be substituted with the correct command join
      # character ('&&' for Windows cmd, ';' for all others)
      $submit{$exe} = join("\n", grep { defined } @{$submit{$exe}});
      # Arrange for mini-batch files to work
      if ($^O =~ /MSWin/ &&
          $submit{$exe} =~ /(?:\&\&|\n)/ &&
          $submit{$exe} !~ /^cmd /) {
        $submit{$exe} = 'cmd /E:ON /D /C '.$submit{$exe};
      }
    }
    return %submit;
}

sub assemble_monitor_wrapper {
    # Assemble possibly multi-line monitor_wrapper
    my ($me) = @_;
    my @cmds = ();
    
    foreach my $line (grep { /^monitor_wrapper\d*$/ } $me->list_keys) {
      my ($idx) = $line =~ m/^monitor_wrapper(\d*)$/;
      my $val = $me->accessor($line);
      $cmds[$idx] = $val;
    }

    my $cmd = join("\n", @cmds);
    # Arrange for mini-batch files to work
    if (   $^O =~ /MSWin/
        && $cmd =~ /(?:\&\&|\n)/
       	&& $cmd !~ /^cmd /) {
	$cmd = 'cmd /E:ON /D /C '.$cmd;
    }
    if ($cmd =~ m#^cmd # && $^O =~ /MSWin/) {
	# Convert line feeds into && for cmd.exe
	$cmd =~ s/[\r\n]+/\&\&/go;
    } else {
	$cmd =~ s/[\r\n]+/;/go;
    }

    return $cmd;
}

sub run_benchmark {
    my ($me, $num_copies, $setup, $is_build, $iter, $is_training) = @_;
    my ($start, $stop, $elapsed);
    my @skip_timing = ();
    my %err_seen = ();
    my $specperl = ($^O =~ /MSWin/) ? 'specperl.exe' : 'specperl';
    my $submit;
    my %submit = $me->assemble_submit();
    my $origwd = main::cwd();
    my $do_monitor =    !(istrue($me->plain_train) && $is_training)
                     && !::check_list($me->no_monitor, $me->size);
    my $tune = $me->tune;
    my $ext = $me->ext;
    my $env_vars = istrue($me->env_vars) && ($::lcsuite !~ /^cpu2/ || !istrue($me->reportable));

    my @dirs = @{$me->dirlist}[0..$num_copies-1];
    my $error = 0;

    my $result = $me->make_empty_result($num_copies, $iter, undef, $is_training);

    if (!defined($result)) {
      Log(0, "ERROR: ".$me->benchmark." does not support workload size ".$me->size."\n");
      return undef;
    }

    if (istrue($me->accessor_nowarn('fail')) ||
        istrue($me->accessor_nowarn('fail_run'))) {
        Log(0, "ERROR: fail or fail_run set for this benchmark\n");
        $result->{'valid'} = 'RE';
        push (@{$result->{'errors'}}, "failed by request\n");
        return $result;
    }

    my $path = $dirs[0]->path;
    chdir($path);

    # Munge the environment now so it can be seen by pre_run() and invoke()
    # and be stored in the command file
    my %oldENV = %ENV;
    main::munge_environment($me) if $env_vars;
    $ENV{'OMP_NESTED'} = 'FALSE' if istrue($me->reportable);
    if ($::lcsuite =~ /^omp20(01|12)$/ || $::lcsuite eq 'cpuv6') {
        my $threads = $me->accessor_nowarn('threads');
        if (defined($threads) && $threads > 0) {
            $ENV{'OMP_NUM_THREADS'} = $threads;
        } else {
            delete $ENV{'OMP_NUM_THREADS'};
        }
    }

    if ($me->pre_run(map { $_->path } @dirs)) {
        Log(0, "ERROR: pre-run failed for ".$me->benchmark."\n");
        $result->{'valid'} = 'TE';
        push (@{$result->{'errors'}}, "pre_run failed\n");
        %ENV = %oldENV if $env_vars;
        return $result;
    }
    $me->unshift_ref({ 'iter' => 0, 'command' => '', 'commandexe' => '',
		       'copynum' => 0, });
    $me->push_ref   ({ 'fdocommand' => '', 'monitor_wrapper' => '',
		       'monitor_specrun_wrapper' => '', });
    my @newcmds;

    push @newcmds, '-S '.$me->stagger if istrue($me->shrate);
    my $bindval = $me->bind;
    my @bindopts = (reftype($bindval) eq 'ARRAY') ? @{$bindval} : ();
    my $do_binding = defined($bindval) && @bindopts;
    for(my $i = 0; $i < @dirs; $i++) {
	my $dir = $dirs[$i];
        if ($do_binding) {
	    $bindval = $bindopts[$i % ($#bindopts + 1)];
	    $bindval = '' unless defined($bindval);
	    push @newcmds, "-b $bindval";
	}
	push @newcmds, '-C ' . $dir->path;
    }
    if (istrue($me->fake)) {
      Log(0, "\nBenchmark invocation\n");
      Log(0, "--------------------\n");
    }

    my $workload_num = 0;
    for my $obj ($me->invoke) {
        if (!defined($obj)) {
            # invoke() is unhappy
            $result->{'valid'} = 'TE';
            push (@{$result->{'errors'}}, "invoke() failed\n");
            %ENV = %oldENV if $env_vars;
            return $result;
        }

        if ($::lcsuite eq 'accelv1') {
            # Append the supplied values for platform and device
            unshift @{$obj->{'args'}}, '--device', $me->device if $me->device ne '';
            unshift @{$obj->{'args'}}, '--platform', $me->platform if $me->platform ne '';
        }

	my $command = ::path_protect(jp('..', basename($path), $obj->{'command'}));

        my $shortexe = $obj->{'command'};
        $shortexe =~ s/_$tune\.$ext//;
        $submit = exists($submit{$shortexe}) ? $submit{$shortexe} : $submit{'default'};
	# Protect path separators in submit; they'll be put back later
	$submit = ::path_protect($submit);
	$me->accessor_nowarn('commandexe', $command);
	$command .= ' ' . join (' ', @{$obj->{'args'}}) if @{$obj->{'args'}};
	if (istrue($me->command_add_redirect)) {
	    $command .= ' < '.$obj->{'input'} if ($obj->{'input'} ne '');
	    $command .= ' > '.$obj->{'output'} if ($obj->{'output'} ne '');
	    $command .= ' 2>> '.$obj->{'error'} if ($obj->{'error'} ne '');
	}
	$command = ::path_protect($command);
	$me->command($command);

	## expand variables and values in the command line
	if ($me->fdocommand ne '') {
	    $command = ::command_expand($me->fdocommand, 
                                          [ $me,
                                            {
                                             'iter' => $iter,
                                             'workload' => $workload_num,
                                            }
                                          ]);
	    $command = ::path_protect($command);
	    $me->command($command);
	} elsif ($me->assemble_monitor_wrapper ne '' && $do_monitor) {
            my $wrapper = $me->assemble_monitor_wrapper;
	    $wrapper = ::path_protect($wrapper);
	    $command = ::command_expand($wrapper,
                                          [ $me,
                                            {
                                             'iter' => $iter,
                                             'workload' => $workload_num,
                                            }
                                          ]);
	    $command = ::path_protect($command);
	    $me->command($command);
	}

	$me->copynum(0);
	if ($submit
            &&
            # Submit should only be used for training runs when plain_train is
            # unset and use_submit_for_speed is set.
            (!$is_training ||
              (!istrue($me->plain_train) &&
               istrue($me->use_submit_for_speed))
            )
            &&
	    (istrue($me->rate) ||
             istrue($me->shrate) ||
	     istrue($me->use_submit_for_speed))) {
            Log(40, "Submit command for ".$me->descmode." (workload $workload_num):\n  ".::path_unprotect($submit)."\n");
	    $command = ::command_expand($submit,
                                          [ $me,
                                            {
                                             'iter' => $iter,
                                             'workload' => $workload_num
                                            }
                                          ]);
            $command = ::path_protect($command);
	    $me->command($command);
            $result->{'submit'} = 1;
	}
	my $opts = '';
	$opts .= '-i '. $obj->{'input'}  .' ' if (exists $obj->{'input'});
	$opts .= '-o '. $obj->{'output'} .' ' if (exists $obj->{'output'});
	$opts .= '-e '. $obj->{'error'}  .' ' if (exists $obj->{'error'});
        if ($command =~ m#^cmd # && $^O =~ /MSWin/) {
            # Convert line feeds (shouldn't exist anyway) into && for cmd.exe
	    $command =~ s/[\r\n]+/\&\&/go;
        } else {
	    $command =~ s/[\r\n]+/;/go;
        }
        $command = ::path_unprotect($command);
        $me->command($command);
	push @newcmds, "$opts$command";
        push @skip_timing, $obj->{'notime'} || 0;
        $workload_num++;
    }

    if (!$setup && !istrue($me->fake)) {
        Log(150, "Commands to run:\n");
        my $i = 0;
        for($i = 0; $i < @newcmds && $newcmds[$i] =~ /^-[SbC]/; $i++) {
            Log(150, "    $newcmds[$i]\n");
        }
        # The apparent $i/$j confusion stems from the fact that @newcmds and
        # @skip_timing are NOT fully parallel arrays.
        for(my $j = 0; $i < @newcmds; $i++, $j++) {
            Log(150, "    $newcmds[$i] (".($skip_timing[$j] ? 'NOT ' : '')."timed)\n");
        }
    }

    my $absrunfile = jp($path, $me->commandfile);
    my $resfile    = jp($path, $me->commandoutfile);
    {
	my $fh = new IO::File ">$absrunfile";
	if (defined($fh)) {
            $me->specinvoke_dump_env($fh);
	    print $fh join ("\n", @newcmds), "\n";
	    $fh->close;
            my $expected_length = length(join("\n", @newcmds));
            $expected_length++ unless $expected_length;
            if (-s $absrunfile < $expected_length) {
              Log(0, "\n$absrunfile is short; evil is afoot,\n  or the benchmark tree is corrupted or incomplete.\n");
              main::do_exit(1);
            }
	} else {
	    Log(0, "Error opening $absrunfile for writing!\n");
	    main::do_exit(1);
	}
    }

    if (!$setup) {
	# This is the part where the benchmark is actually run...
	my @specrun = (jp($me->top, 'bin', $me->specrun),
		       '-d', $path,
		       '-e', $me->commanderrfile,
		       '-o', $me->commandstdoutfile,
		       '-f', $me->commandfile,
		       );
	push @specrun, '-r' if istrue($me->command_add_redirect);
	push @specrun, '-nn' if istrue($me->fake);
	if ($me->no_input_handler =~ /null/io) {
	    push @specrun, '-N';
	} elsif ($me->no_input_handler =~ /(?:zero|file)/io) {
	    push @specrun, '-Z';
	} else {
	    push @specrun, '-C';
	}
        # There's no point in continuing if one part of the benchmark fails.
        # Stop to avoid destroying evidence in the run directory.
        push @specrun, '-q' if ::specinvoke_can('-q');
	my $command =join (' ', @specrun);
	$me->command($command);
	if ($me->monitor_specrun_wrapper ne '' && $do_monitor) {
	    $command = ::command_expand($me->monitor_specrun_wrapper, [ $me, { 'iter', $iter } ]);
	    $command = "echo \"$command\"" if istrue($me->fake);
	}
	main::monitor_pre_bench($me, { 'iter' => $iter }) if $do_monitor;
	if ($me->delay > 0 && !istrue($me->reportable)) {
	    Log(190, "Entering user-requested pre-invocation sleep for ".$me->delay." seconds.\n");
	    sleep $me->delay;
	}

	Log(191, "Specinvoke: $command\n") unless istrue($me->fake);

        # Begin power measurement if requested
        if (!$::from_runspec && istrue($me->power) && !$is_training) {
            my $isok = ::meter_start($me->benchmark,
                                     {
                                       'a' => { 'default' => $me->current_range },
                                       'v' => { 'default' => $me->voltage_range },
                                     },
                                    @{$me->powermeterlist});
            if (!$isok) {
                Log(0, "ERROR: Power analyzers could not be started\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) power analyzers could not be started\n");
            }
            $isok = ::meter_start($me->benchmark, undef, @{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Temperature meters could not be started\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) temperature meters could not be started\n");
            }
        }

	$start = time;
	my $rc;
        my $outname = istrue($me->fake) ? 'benchmark_run' : undef;
	if ($me->monitor_specrun_wrapper ne '' && $do_monitor) {
	    $rc = ::log_system_noexpand($command, $outname);
	} else {
	    $rc = ::log_system_noexpand(join(' ', @specrun), $outname);
	}
	$stop = time;
	$elapsed = $stop-$start;
	%ENV = %oldENV if $env_vars;

        # End the power measurement and collect the results
        if (!$::from_runspec && istrue($me->power) && !$is_training) {
            my $isok = ::meter_stop(@{$me->powermeterlist});
            if (!$isok) {
                Log(0, "ERROR: Power analyzers could not be stopped\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) power analyzers could not be stopped\n");
            }
            $isok = ::meter_stop(@{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Temperature meters could not be stopped\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) temperature meters could not be stopped\n");
            }

            # Give the meters a second to stop
            sleep 1;

            # Read the info and store it in the result object
            my ($total, $avg, $min, $max, $max_uncertainty, $avg_uncertainty, $statsref, @list);

            # First, power:
            ($isok, $total, $avg, $max_uncertainty, $avg_uncertainty, @list) = ::power_analyzer_watts($me->meter_errors_percentage, @{$me->powermeterlist});
            if (!$isok || !defined($avg)) {
                Log(0, "ERROR: Reading power analyzers returned errors\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) reading power analyzers returned errors\n");
            }
            push @{$result->{'powersamples'}}, @list;
            $result->{'avg_power'} = $total;
            $result->{'min_power'} = -1;        # Placeholder until extract_samples
            $result->{'max_power'} = -1;        # Placeholder until extract_samples
            $result->{'max_uncertainty'} = $max_uncertainty;
            $result->{'avg_uncertainty'} = $avg_uncertainty;
            ::extract_ranges($result, $result->{'powersamples'}, '', @{$me->powermeterlist});

            # Now, temperature:
            ($isok, $statsref, @list) = ::temp_meter_temp_and_humidity($me->meter_errors_percentage, @{$me->tempmeterlist});
            if (!$isok) {
                Log(0, "ERROR: Reading temperature meters returned errors\n");
                $result->{'valid'} = 'PE';
                push (@{$result->{'errors'}}, "(PE) reading temperature meters returned errors\n");
            }
            $statsref = {} unless reftype($statsref) eq 'HASH';
            foreach my $thing (qw(temperature humidity)) {
                $statsref->{$thing} = [] unless reftype($statsref->{$thing}) eq 'ARRAY';
            }
            ($avg, $min, $max) = @{$statsref->{'temperature'}};
            push @{$result->{'tempsamples'}}, @list;
            $result->{'avg_temp'} = defined($avg) ? $avg : 'Not Measured';
            $result->{'min_temp'} = defined($min) ? $min : 'Not Measured';
            $result->{'max_temp'} = defined($max) ? $max : 'Not Measured';
            ($avg, $min, $max) = @{$statsref->{'humidity'}};
            $result->{'avg_hum'} = defined($avg) ? $avg : 'Not Measured';
            $result->{'min_hum'} = defined($min) ? $min : 'Not Measured';
            $result->{'max_hum'} = defined($max) ? $max : 'Not Measured';

            # Check the limits
            if (   (istrue($me->reportable) || $result->{'min_temp'} ne 'Not Measured')
                && $::global_config->{'min_temp_limit'}
                && $result->{'min_temp'} < $::global_config->{'min_temp_limit'}) {
                Log(0, "ERROR: Minimum temperature during the run (".$result->{'min_temp'}." degC) is less than the minimum allowed (".$::global_config->{'min_temp_limit'}." degC)\n");
                $result->{'valid'} = 'EE';
                push @{$result->{'errors'}}, "(EE) Minimum allowed temperature exceeded\n";
            }
            if (   (istrue($me->reportable) || $result->{'max_hum'} ne 'Not Measured')
                && $::global_config->{'max_hum_limit'}
                && $result->{'max_hum'} > $::global_config->{'max_hum_limit'}) {
                Log(0, "ERROR: Maximum humidity during the run (".$result->{'max_hum'}."%) is greater than the maximum allowed (".$::global_config->{'max_hum_limit'}."%)\n");
                $result->{'valid'} = 'EE';
                push @{$result->{'errors'}}, "(EE) Maximum allowed humidity exceeded\n";
            }
        }

	if ($me->delay > 0 && !istrue($me->reportable)) {
	    Log(190, "Entering user-requested post-invocation sleep for ".$me->delay." seconds.\n");
	    sleep $me->delay;
	}

	main::monitor_post_bench($me, { 'iter' => $iter }) if $do_monitor;

	$me->pop_ref();
	$me->shift_ref();
	if (defined($rc) && $rc) {
	    $result->{'valid'} = 'RE';
	    Log(0, "\n".$me->benchmark.': '.$me->specrun.' non-zero return code (exit code='.WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n\n");
	    push (@{$result->{'errors'}}, $me->specrun.' non-zero return code (exit code='.WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n");
	    log_err_files($path, 1, \%err_seen);
	}

	my $fh = new IO::File "<$resfile";
	if (defined $fh) {
	    my $error = 0;
	    my @child_times = ( );
	    my @counts = ();
            my @power_intervals = ();
	    while (<$fh>) {
                # Make sure the environment gets into the debug log
                Log(99, $_);
		if (m/child finished:\s*(\d+),\s*(\d+),\s*(\d+),\s*(?:sec=)?(\d+),\s*(?:nsec=)?(\d+),\s*(?:pid=)?\d+,\s*(?:rc=)?(\d+)/) {
		    my ($num, $ssec, $snsec, $esec, $ensec, $rc) =
			($1, $2, $3, $4, $5, $6);
                    $counts[$num] = 0 unless defined($counts[$num]);
                    my $skip_timing = $skip_timing[$counts[$num]] || 0;
		    $counts[$num]++;
		    if ($rc != 0) {
			$error = 1;
			$result->{'rc'} = $rc;
			$result->{'valid'} = 'RE';
			Log(0, "\n".$me->benchmark.": copy $num non-zero return code (exit code=".WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n\n");
                        push (@{$result->{'errors'}}, "copy $num non-zero return code (exit code=".WEXITSTATUS($rc).', signal='.WTERMSIG($rc).")\n");
                        log_err_files($path, 0, \%err_seen);
		    }
		    Log(110, "Workload elapsed time ($num:$counts[$num]) = ".($esec + ($ensec/1000000000))." seconds".($skip_timing ? ' (not counted in total)' : '')."\n");
                    $child_times[$num] = { 'time' => 0, 'untime' => [0, 0], 'num' => $num } unless defined($child_times[$num]);
                    $child_times[$num]->{'lastline'} = "Copy $num of ".$me->benchmark.' ('.$me->tune.' '.$me->size.") run ".($iter+1)." finished at ".main::ctime($ssec+($snsec/1000000000)).".  Total elapsed time: ";
                    if (!$skip_timing) {
                        $child_times[$num]->{'time'} += $esec + ($ensec/1000000000);
                        # When adding power intervals, round end times and
                        # durations up to the nearest second.
                        # This will help catch intervals for very short-
                        # running benchmarks, and won't adversely affect
                        # long-running ones.
                        ::add_interval(\@power_intervals,
                                       int($ssec + ($snsec/1000000000) + 0.5),
                                       int($esec + ($ensec/1000000000) + 0.5));
                        # Make a check for extra stupid times
                        my $lifetime = time - $main::runspec_time;
                        $lifetime++ unless ($lifetime);
                        if ($child_times[$num]->{'time'} > $lifetime) {
                            # Something stupid has happened, and an elapsed time
                            # greater than the total amount of time in the run so far
                            # has been claimed.  This is obviously big B.S., so just
                            # croak.
                            Log(0, "\nERROR: Claimed elapsed time of ".$child_times[$num]->{'time'}." for ".$me->benchmark." is longer than\n       total run time of $lifetime seconds.\nThis is extremely bogus and the run will now be stopped.\n");
                            main::do_exit(1);
                        }
                    } else {
                        # Remember the elapsed time per child so that it can be
                        # subtracted from the reported time.
                        $child_times[$num]->{'untime'}->[0] += $esec;
                        $child_times[$num]->{'untime'}->[1] += $ensec;
                    }
		} elsif (m/timer ticks over every (\d+) ns/) {
                    # Figure out the number of significant decimal places
                    # for the reported times.
                    my $tmpdp = new Math::BigFloat $1+0;
                    $tmpdp->bdiv(1_000_000_000);  # Convert to seconds
                    $tmpdp->blog(10);             # Get number of decimal places
                    if ($tmpdp->is_neg()) {
                        $result->{'dp'} = abs(int($tmpdp->bstr() + 0));
                    } else {
                        # This shouldn't happen.  If it does, we're screwed --
                        # it means the timer has granularity of at least 1
                        # second.  So just don't figure the decimal places.
                        Log(0, "WARNING: System timer resolution is less than .1 second\n");
                    }
                } elsif (m/runs elapsed time:\s*(\d+),\s*(\d+)/) {
		    $result->{'reported_sec'}  = $1;
		    $result->{'reported_nsec'} = $2;

                    if ($::lcsuite !~ /cpu(?:2006|v6)/) {
                        # Now subtract the _longest_ of the children's
                        # "un"times.  Since CPU is excluded, and none
                        # of the other suites use rate mode, this should
                        # always only be one number, but let's not count on
                        # that.
                        my @untimes = sort {
                                             $b->{'untime'}->[0]+($b->{'untime'}->[1]/1_000_000_000) <=> $a->{'untime'}->[0]+($a->{'untime'}->[1]/1_000_000_000)
                                           } @child_times;
                        my ($untime_sec, $untime_nsec) = @{$untimes[0]->{'untime'}};
                        $result->{'reported_sec'} -= $untime_sec;
                        $result->{'reported_nsec'} -= $untime_nsec;
                        if ($result->{'reported_nsec'} < 0) {
                            $result->{'reported_sec'}--;
                            $result->{'reported_nsec'} += 1_000_000_000;
                        }
                    }
		}
	    }
	    $fh->close;
	    foreach my $ref (@child_times) {
		next unless defined($ref);
		if (ref($ref) ne 'HASH') {
		    Log(0, "Non-HASH ref found in child stats: $ref\n");
		} else {
		    Log(125, $ref->{'lastline'}.$ref->{'time'}."\n");
                    $result->{'copytime'}->[$ref->{'num'}] = $ref->{'time'};
		}
	    }

            if (!$::from_runspec && istrue($me->power) && !$is_training) {
                # Now trim up the power samples.  This will select based
                # on sample time, discard (if applicable), and recalculate
                # min/avg/max.
                my ($newavg, $junk, $newmin, $newmax, @newsamples) = ::extract_samples($result->{'powersamples'}, \@power_intervals, $me->discard_power_samples);
                if (defined($newavg) && @newsamples) {
                    ($result->{'avg_power'}, $result->{'min_power'}, $result->{'max_power'}, @{$result->{'powersamples'}}) = ($newavg, $newmin, $newmax, @newsamples);
                } else {
                    Log(0, "ERROR: No power samples found during benchmark run\n");
                    $result->{'valid'} = 'PE';
                    push @{$result->{'errors'}}, "(PE) no power samples found during benchmark run\n";
                }
            }

	} elsif (!istrue($me->fake)) {
	    $result->{'valid'} = 'RE';
	    Log(0, "couldn't open specrun result file '$resfile'\n");
	    push (@{$result->{'errors'}}, "couldn't open specrun result file\n");
	}

        # For regular runs, proceed to validation even if there were
        # measurement (PE) or environmental (EE) errors.  This is so
        # that the result can potentially be reformatted with --nopower.
        # Don't want to make a no-validation loophole. :)
	return $result if (($error || $result->{'valid'} !~ /^(?:S|PE|EE)$/
			    || @{$result->{'errors'}}+0 > 0)
			   && $me->accessor_nowarn('fdocommand') ne '');
    } else {
        # Just in case
        %ENV = %oldENV if $env_vars;
    }

# Now make sure that the results compared!
    if ($me->action eq 'only_run' && !$is_training) {
	$result->{'valid'} = 'R?' if $result->{'valid'} eq 'S';
    } elsif ($result->{'valid'} =~ /^(?:S|PE|EE)$/) {
	my $size        = $me->size;
	my $size_class  = $me->size_class;
	my $tune        = $me->tune;
	my $comparedir  = $dirs[0]->path;
	my $comparename = jp($comparedir, $me->comparefile);

        
        if (istrue($me->fake)) {
          Log(0, "\nBenchmark verification\n");
          Log(0, "----------------------\n");
        }

	if (!$setup) {
	    # If we're just setting up, there won't be any output files
	    # to fix up.
	    if ($me->pre_compare(@dirs)) {
		Log(0, "pre_compare for " . $me->benchmark . " failed!\n");
	    }
	}

	my $comparecmd = new IO::File ">$comparename";
	if (!defined $comparecmd) {
	    $result->{'valid'} = 'TE';
	    push (@{$result->{'errors'}}, "Unable to open compare commands file for writing");
	} else {
            $me->specinvoke_dump_env($comparecmd);
	    my $num_output_files = 0;
            my $expected_length = 0;
	    for my $obj (@dirs) {
		my $path = $obj->path;
		my $basecmd = "-c $path ";

		Log(145, "comparing files in '$path'\n") unless (istrue($me->fake) || $setup);
		for my $absname ($me->output_files_abs) {
		    my $relname = basename($absname, '.bz2');
		    my $opts = { 'cw'         => $me->compwhite ($size, $size_class, $tune, $relname),
				 'abstol'     => $me->abstol    ($size, $size_class, $tune, $relname),
				 'floatcompare' => $me->floatcompare,
				 'calctol'    => $me->calctol,
				 'reltol'     => $me->reltol    ($size, $size_class, $tune, $relname),
				 'obiwan'     => $me->obiwan    ($size, $size_class, $tune, $relname),
				 'skiptol'    => $me->skiptol   ($size, $size_class, $tune, $relname),
				 'skipabstol' => $me->skipabstol($size, $size_class, $tune, $relname),
				 'skipreltol' => $me->skipreltol($size, $size_class, $tune, $relname),
				 'skipobiwan' => $me->skipobiwan($size, $size_class, $tune, $relname),
				 'binary'     => $me->binary    ($size, $size_class, $tune, $relname),
				 'ignorecase' => $me->ignorecase($size, $size_class, $tune, $relname),
			     };

		    Log(150, "comparing '$relname' with ".join(', ', map { "$_=$opts->{$_}" } sort keys %$opts)."\n") unless (istrue($me->fake) || $setup);

		    my $cmd = $basecmd . "-o $relname.cmp " . "$specperl " . jp($me->top, 'bin', $me->specdiff) . 
			    ' -m -l ' . $me->difflines . ' ';
		    # Add options that have skip- variants and take args
		    foreach my $cmptype (qw(abstol reltol skiptol)) {
			if (defined($opts->{$cmptype}) &&
			    ($opts->{$cmptype} ne '')) {
			    $cmd .= " --$cmptype $opts->{$cmptype} ";
			}
			if (defined($opts->{"skip$cmptype"}) &&
			    ($opts->{"skip$cmptype"} ne '')) {
			    $cmd .= qq/ --skip$cmptype $opts->{"skip$cmptype"} /;
			}
		    }
		    # skipobiwan is special because obiwan is a switch
		    if (defined($opts->{'skipobiwan'}) &&
			($opts->{'skipobiwan'} ne '')) {
			$cmd .= " --skipobiwan $opts->{'skipobiwan'} ";
		    }
		    # Add options for switches
		    foreach my $cmptype (qw(calctol obiwan binary cw
                                            floatcompare ignorecase)) {
			if (defined($opts->{$cmptype}) && $opts->{$cmptype}) {
			    $cmd .= " --$cmptype ";
			}
		    }
		    $cmd .= $absname . ' ' . $relname;
		    $comparecmd->print("$cmd\n");
                    $expected_length += length($cmd);
		    $num_output_files++;
		}
	    }
	    $comparecmd->close();
	    return $result if $setup;
            if ($num_output_files == 0) {
              Log(0, "\nNo output files were found to compare!  Evil is afoot, or the benchmark\n  tree is corrupt or incomplete.\n\n");
              main::do_exit(1);
            }
            
            if (-s $comparename < $expected_length) {
              Log(0, "\nERROR: The compare commands file ($comparename) is short!\n       Please make sure that the filesystem is not full.\n");
              $result->{'valid'} = 'TE';
              push (@{$result->{'errors'}}, "Compare commands file was short");
            } else {
              my $num_compares = $me->max_active_compares;
              # If max_active_compares isn't set, this will ensure that we
              # do one compare (at a time) per run directory
              $num_compares = @dirs+0 if $num_compares == 0;
              # If we try to run more compares than the total number of output
              # files to compare (copies * output files), then one will exit,
              # and the compare will fail, even if everything else is okay.
              if ($num_compares > $num_output_files) {
                  $num_compares = $num_output_files;
              }
              my @specrun = (jp($me->top, 'bin', $me->specrun),
                          '-E',
                          '-d', $comparedir,
                          '-c', $num_compares,
                          '-e', $me->compareerrfile,
                          '-o', $me->comparestdoutfile,
                          '-f', $me->comparefile,
                          '-k',
                          );
              push @specrun, '-nn' if istrue($me->fake);
              Log(191, 'Specinvoke: ', join (' ', @specrun), "\n") unless istrue($me->fake);
	      my $outname = istrue($me->fake) ? 'compare_run' : undef;
              my $rc = ::log_system_noexpand(join(' ', @specrun), $outname, 0, undef, 1);
              if (defined($rc) && $rc) {
                  log_err_files($path, 1, \%err_seen);
              }
	      # Scan the specdiff output files for indications of completed
	      # runs.
	      my @misfiles = ();
	      my %specdiff_errors = ();
              my @missing = ();
              my @empty = ();
	      for my $obj (@dirs) {
		  my $file;
		  my $dh = new IO::Dir $obj->path;
		  while (defined($file = $dh->read)) {
		      next if $file !~ m/\.(mis|cmp)$/i;
		      if ($1 eq 'mis') {
			  # Remember it for later
			  push @misfiles, jp($obj->path, $file);
			  next;
		      }
		      my ($basename) = $file =~ m/(.*)\.cmp$/;
		      my $cmpname = jp($obj->path, $file);
                      my $orig_file = jp($obj->path, $basename);
                      if (!-e $orig_file) {
                          push @missing, $orig_file;    # Shouldn't happen here
                      } elsif (-s $orig_file <= 0) {
                          push @empty, $orig_file;
                      } else {
                          my $diff_ok = 0;
                          my $fh = new IO::File "<$cmpname";
                          if (!defined($fh)) {
                              Log(0, "*** specdiff error on $basename; no output was generated\n");
                              $rc = 1 unless $rc;
                          } else {
                              # Just read it in to make sure specdiff said "all ok"
                              while(<$fh>) {
                                  $diff_ok = 1 if /^specdiff run completed$/o;
                                  last if $diff_ok;
                              }
                              $fh->close();
                          }
                          if ($diff_ok == 0) {
                              $specdiff_errors{$cmpname}++;
                              $rc = 1 unless $rc;
                          }
                      }
		  }
	      }
              if ($rc) {
                  $result->{'valid'} = 'VE' if $result->{'valid'} =~ /^(?:S|PE|EE)$/;
                  push (@{$result->{'errors'}}, "Output miscompare");
                  my $logged = 0;
		  while (defined(my $misname = shift(@misfiles))) {
		      my $cmpname = $misname;
                      $cmpname =~ s/\.mis$/.cmp/o;
		      my $basename = basename($misname, '.mis');
		      my $dirname = dirname($misname);
                      my $orig_file = ::jp($dirname, $basename);

                      if (!-e $orig_file) {
                          push @missing, $orig_file;    # Shouldn't happen here
                      } elsif (-s $orig_file <= 0) {
                          push @empty, $orig_file unless grep m/^\Q$orig_file\E/, @empty;
                      } else {
                          my $msg = "\n*** Miscompare of $basename";
                          if (-s $misname > 0) {
                              $msg .= "; for details see\n    $misname\n";
                          } else {
                              $msg .= ", but the miscompare file is empty.\n";
                          }
                          Log (0, $msg);
                          $logged = 1;
                          my $fh = new IO::File "<$misname";
                          if (!defined $fh) {
                              if ($specdiff_errors{$cmpname}) {
                                  Log(0, "specdiff did not complete successfully!\n");
                              } else {
                                  Log (0, "Can't open miscompare file!\n");
                              }
                          } else {
                              while (<$fh>) {
                                  Log (120, $_);
                              }
                              $fh->close();
                          }
                          delete $specdiff_errors{$cmpname};
                      }
		  }
                  if (@missing) {
                      if (@missing > 1) {
                          Log(0, "\n*** The following output files were expected, but were not found:\n");
                      } else {
                          Log(0, "\n*** The following output file was expected, but does not exist:\n");
                      }
                      Log(0, '      '.join("\n      ", @missing)."\n".
                          "    This often means that the benchmark did not start, or failed so\n".
                          "    quickly that some output files were not even opened.\n". 
                          "    Possible causes may include:\n".
                          "      - Did you run out of memory? (Check both your process limits and the system limits.)\n".
                          "      - Did you run out of disk space? (Check both your process quotas and the actual disk.)\n".
                          "    See also any specific messages printed in .err or .mis files in the run directory.\n\n");
                      foreach my $missing_file (@missing) {
                          delete $specdiff_errors{$missing_file.'.cmp'};
                      }
                      $logged = 1;
                  }
                  if (@empty) {
                      if (@empty > 1) {
                          Log(0, "\n*** The following output files had no content:\n");
                      } else {
                          Log(0, "\n*** The following output file had no content:\n");
                      }
                      Log(0, '      '.join("\n      ", @empty)."\n".
                          "    This often means that the benchmark did not start, or failed so\n".
                          "    quickly that some output files were not written.\n".
                          "    Possible causes may include:\n".
                          "      - Did you run out of memory? (Check both your process limits and the system limits.)\n".
                          "      - Did you run out of disk space? (Check both your process quotas and the actual disk.)\n".
                          "    See also any specific messages printed in .err or .mis files in the run directory.\n\n");
                      foreach my $empty_file (@empty) {
                          delete $specdiff_errors{$empty_file.'.cmp'};
                      }
                      $logged = 1;
                  }
		  foreach my $diff_error (sort keys %specdiff_errors) {
		      Log(0, "\n*** Error comparing $diff_error: specdiff did not complete\n");
		  }
                  Log(0, "\nCompare command returned $rc!\n") unless $logged;
	      }
	  }
	}
    }

    return $result if ($me->accessor_nowarn('fdocommand') ne '');

    my $reported_sec  = $result->{'reported_sec'};
    my $reported_nsec = $result->{'reported_nsec'};
    my $reported = $reported_sec + ::round($reported_nsec / 1_000_000_000, $result->{'dp'});
    $result->{'reported_time'} = $reported;
    $result->{'energy'}        = (defined($reported) && $reported) ? ::round($result->{'avg_power'} * $reported, $result->{'dp'}) : 0;

    if ($me->size_class eq 'ref') {
	my $reference = $me->reference;
	my $reference_energy = $me->reference_power * $reference;

	$result->{'ratio'}         = (defined($reported) && $reported) ? ::round($reference / $reported, $result->{'dp'}) : 0;
	$result->{'energy_ratio'}  = ($result->{'energy'} > 0) ? ::round($reference_energy / $result->{'energy'}, $result->{'dp'}) : 0;
        # To figure out the multipler, get the list of benchset(s) that the
        # benchmark is in, and use the multiplier for the first one
        # that generates output.
        # NOTE: This means that it won't work to have the same benchmark in
        #       two or more benchsets with different multipliers!
        my @bsets = $::global_config->benchmark_in_sets($me->benchmark);
        @bsets = grep { $::global_config->{'benchsets'}->{$_}->{'output'} } @bsets;
        my $bset = shift(@bsets);
        my $mult = 0;
        if (!defined($bset)) {
            ::Log(0, "ERROR: ".$me->benchmark." was not found in any benchset!\n");
        } elsif (istrue($me->rate)) {
            $mult = $::global_config->{'benchsets'}->{$bset}->{'rate_multiplier'};
        } else {
            $mult = $::global_config->{'benchsets'}->{$bset}->{'speed_multiplier'};
        }
        ::Log(80, "Selected multiplier of $mult for ".$me->descmode."\n");

	if (istrue($me->rate)) {
	    $result->{'ratio'} *= $num_copies * $mult;
	    $result->{'energy_ratio'} *= $num_copies;
	} else {
	    $result->{'ratio'} *= $mult;
	}
    }

    if (!istrue($me->fake)) {
      Log (155, "Benchmark Times:\n",
               '  Start:    ', ::ctime($start), " ($start)\n",
               '  Stop:     ', ::ctime($stop),  " ($stop)\n",
               '  Elapsed:  ', ::to_hms($elapsed), " ($elapsed)\n",
               '  Reported: ', "$reported_sec $reported_nsec $reported\n");
    }

    push (@{$me->{'result_list'}}, $result);
    chdir($origwd);
    return $result;
}

sub check_threads {
    # Placeholder function
    return 0;
}

sub pre_build {
    # Placeholder function
    return 0;
}

sub post_setup {
    # Placeholder function
    return 0;
}

sub pre_compare {
    return 0;
}

sub pre_run {
    # Placeholder function
    return 0;
}

sub result_list {
    my ($me, $copies) = @_;

    if ($::lcsuite =~ /cpu(?:2006|v6)/ && defined $copies) {
	return grep ($_->copies == $copies, @{$me->{'result_list'}});
    } else {
	return @{$me->{'result_list'}};
    }
}

sub ratio {
    my ($me, $num_copies) = @_;
    my @res = @{$me->{'result_list'}};
    if (defined $num_copies) {
	@res = grep ($_->{'copies'} == $num_copies, @res);
    }
    @res = sort { $a->{'ratio'} <=> $b->{'ratio'} } @{$me->{'result_list'}};
    if (@res % 2) {
	return $res[(@res-1)/2]; # Odd # results, return the median ratio
    } else {
        # For even # of results, return the lower median.
        # See chapter 9 of Cormen, Thomas, et al. _Introduction to Algorithms,
        #   2nd Edtion_. Cambridge: MIT Press, 2001
	return $res[@res/2-1];   # Return the lower median
    }
}

sub lock_listfile {
    my ($me, $type) = @_;

    my $subdir = $me->expid;
    $subdir = undef if ($subdir eq '');
    my $path = $me->{'path'};
    if ($me->output_root ne '') {
      my $oldtop = ::make_path_re($me->top);
      my $newtop = $me->output_root;
      $path =~ s/^$oldtop/$newtop/;
    }

    my $dir;
    if ($type eq 'build') {
        $dir = jp($path, $::global_config->{'builddir'}, $subdir);
    } else {
        $dir = jp($path, $::global_config->{'rundir'}, $subdir);
    }
    my $file      = jp($dir,  $me->worklist);
    my $obj = Spec::Listfile->new($dir, $file);
    $me->{'listfile'} = $obj;
    return $obj;
}

sub log_err_files {
    my ($path, $specinvoke_problem, $already_done) = @_;

    # Read the contents of the error files (other than speccmds.err and
    # compare.cmd) and put them in the log file
    my $dh = new IO::Dir $path;
    if (!defined($dh)) {
	Log(0, "\nCouldn't log contents of error files from $path: $!\n\n");
	return;
    }
    while (defined(my $file = $dh->read)) {
	next unless ($file =~ /\.err$/o);
	next if exists($already_done->{$file});
	next if (!$specinvoke_problem && $file =~ /(?:compare|speccmds)\.err$/);
	next unless (-f $file);
        next unless (-s $file);
	my $fh = new IO::File "<$file";
	next unless defined($fh);
	my $eol = $/;
	$/ = undef;
	Log(100, "\n****************************************\n");
	Log(100, "Contents of $file\n");
	Log(100, "****************************************\n");
	Log(100, <$fh>."\n");
	Log(100, "****************************************\n");
	$/ = $eol;
        $already_done->{$file}++;
    }
}

# Read and munge the output of 'specmake options'
sub read_compile_options {
    my ($fname, $pass, $compress_whitespace) = @_;
    my $rc = '';

    my $fh = new IO::File "<$fname";
    if (defined $fh) {
        while (<$fh>) {
            if ($^O =~ /MSWin/) {
                # Strip out extra quotes that Windows echo
                # may have left in
                if (s/^"//) {
                    s/"([\012\015]*)$/$1/;
                    s/\\"/"/;
                    s/\\"(?!.*\\")/"/;
                }
            }
            # Knock out unused variables (shouldn't be any)
            next if (/^[CPO]: _/o);
            # Ignore empty variables
            next if (m/^[CPO]: \S+="\s*"$/o);
            # Fix up "funny" compiler variables
            s/^C: (CXX|F77)C=/C: $1=/o;
            # Add the current pass number (if applicable)
            s/:/$pass:/ if $pass ne '';
            if ($compress_whitespace) {
                # Normalize whitespace
                tr/ \012\015\011/ /s;
            } else {
                # Just normalize line endings
                tr/\012\015//d;
            }
            $rc .= "$_\n";
        }
        $fh->close();
    }

    return $rc;
}

# This sets up some default stuff for FDO builds
sub fdo_command_setup {
    my ($me, $targets, $make, @pass) = @_;
    $targets = [] unless (::reftype($targets) eq 'ARRAY');
    my @targets = @$targets;

    my (@commands) = ('fdo_pre0');
    my $tmp = {
	    'fdo_run1'         => '$command',
	};
    for (my $i = 1; $i < @pass; $i++) {
	if ($pass[$i]) {
	    if ($i != 1) {
              foreach my $target (@targets) {
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
		$tmp->{"fdo_make_clean_pass$i"} = "$make fdoclean FDO=PASS$i$targetflag";
              }
	    }
	    if (($i < (@pass-1)) && !exists($tmp->{"fdo_run$i"})) {
		$tmp->{"fdo_run$i"} = '$command';
	    }
	    push (@commands, "fdo_pre_make$i", "fdo_make_clean_pass$i");
	    foreach my $target (sort @targets) {
		my $exe = ($target ne '') ? "_$target" : '';
                my $targetflag = ($target ne '') ? " TARGET=$target" : '';
		$tmp->{"fdo_make_pass${i}${exe}"} ="$make --always-make build FDO=PASS$i$targetflag";
		push @commands, "fdo_make_pass${i}${exe}";
	    }
	    foreach my $thing ("fdo_make_pass$i", "fdo_post_make$i",
			       "fdo_pre$i", "fdo_run$i", "fdo_post$i") {
		if (!grep { /^$thing/ } @commands) {
		    push @commands, $thing;
		}
	    }
	}
    }

    return ($tmp, @commands);
}

sub get_mandatory_option_md5_items {
    my ($me, @extras) = @_;
    my $rc = '';

    # CVT2DEV: $rc = "DEVELOPMENT TREE BUILD\n";
    foreach my $opt (sort (keys %option_md5_include, grep { $_ ne '' } @extras)) {
        my $val = $me->accessor_nowarn($opt);
        if ((::reftype($val) eq 'ARRAY')) {
            $val = join(',', @$val);
        } elsif ((::reftype($val) eq 'HASH')) {
            $val = join(',', map { "$_=>$val->{$_}" } sort keys %$val);
        }
        if (defined($val) && $val ne '') {
            $rc .= "$opt=\"$val\"\n"
        }
    }
    $rc = "Non-makefile options:\n".$rc if $rc ne '';
    return $rc;
}

sub get_srcalt_list {
    my ($me) = @_;

    if ((::reftype($me->srcalt) eq 'ARRAY')) {
        return ( grep { defined($_) && $_ ne '' } @{$me->srcalt} );
    } elsif (   ref($me->srcalt) eq ''
             && defined($me->srcalt)
             && $me->srcalt ne '') {
        return ( $me->srcalt );
    }
    return ();
}

sub note_srcalts {
    my ($me, $md5ref, $nocheck, @srcalts) = @_;
    my $rc = '';

    foreach my $srcalt (@srcalts) {
        my $saref = $me->srcalts->{$srcalt};
        if (!defined($saref) || (::reftype($saref) ne 'HASH')) {
            next unless $nocheck;
            $saref = { 'name' => $srcalt };
        }
        my $tmpstr = $me->benchmark.' ('.$me->tune."): \"$saref->{'name'}\" src.alt was used.";
        if ($md5ref->{'baggage'} !~ /\Q$tmpstr\E/) {
            if ($md5ref->{'baggage'} ne '' && $md5ref->{'baggage'} !~ /\n$/) {
                $md5ref->{'baggage'} .= "\n";
            }
            $md5ref->{'baggage'} .= $tmpstr;

            if ($rc ne '' && $rc !~ /\n$/) {
                $rc .= "\n";
            }
            $rc .= $tmpstr;
        }
    }
    return $rc;
}

sub specinvoke_dump_env {
    my ($me, $fh) = @_;

    return unless defined($fh);

    # Dump the environment into the specinvoke command file opened at $fh
    foreach my $envvar (sort keys %ENV) {
        # Skip read-only variables
        next if ($envvar =~ /^(_|[0-9]|\*|\#|\@|-|!|\?|\$|PWD|SHLVL)$/);
        if ($envvar =~ /\s/) {
            Log(110, "**WARNING: environment variable name '$envvar' contains whitespace and will be skipped in output\n");
            next;
        }
        my $origenvval = $ENV{$envvar};
        my $complaint_key = substr($envvar.$origenvval, 0, 2048); # Let's not hash too much
        if ($origenvval =~ /[\n\r]/) {
            if (!exists($me->config->{'env_hash_complaints'}->{$complaint_key})) {
                Log(110, "**WARNING: environment variable '$envvar' contains embedded CR or LF; they will be converted to spaces\n");
                $me->config->{'env_hash_complaints'}->{$complaint_key} = 1;
            }
            $origenvval =~ s/[\n\r]/ /g;
        }
        my $envval = shell_quote_best_effort($origenvval);
        if (length($envvar) + length($envval) + 6 >= 16384) {
            if (!exists($me->config->{'env_hash_complaints'}->{$complaint_key})) {
                Log(110, "**WARNING: Length of environment variable '$envvar' is too long; must be less than ".(16384 - length($envvar) - 6)." bytes; truncating value\n");
                $me->config->{'env_hash_complaints'}->{$complaint_key} = 1;
            }
            # Set the initial limit to (16KB - length of variable name
            # - 8 (space for '#', ' ', '-E ', '=', '\n', and terminating NULL))
            my $limit;
            do {
                $limit = 16384 - length($envvar) - 8;
                $origenvval = substr($ENV{$envvar}, 0, $limit - (length($envval) - length($origenvval)));
                $origenvval =~ s/\n.*//;        # Just in case
                $envval = shell_quote_best_effort($origenvval);
            } while (length($envval) > $limit);
        }
        print $fh "-E $envvar $envval\n";
    }
}

1;
