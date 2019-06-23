#
# locate.pm
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: locate.pl 1395 2011-11-23 16:48:00Z CloyceS $

use strict;
use IO::Dir;
use Time::HiRes qw(time);

require 'flagutils.pl';

my $version = '$LastChangedRevision: 1395 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'locate.pl'} = $version;

sub locate_benchmarks {
    my ($config) = @_;

    $config->{'formats'} = {} if !exists $config->{'formats'};

    my $benchdir = jp($config->top, $config->benchdir);
    my %seen;
    my $dh = new IO::Dir $benchdir;
    if (!defined $dh) {
        Log(0, "\nCan't open benchmark directory '$benchdir': $!\n");
        do_exit(1);
    }
    while (defined(my $suitename = $dh->read)) {
        next if $suitename =~ /^\./;
        Log(90, "Reading suite directory for '$suitename', '$benchdir'\n");
        my $suitestarttime = Time::HiRes::time;
        my $dir     = jp($benchdir, $suitename);
        my $basedir = $suitename;
        next if !-d $dir;
        my $dh2 = new IO::Dir $dir;
        while (defined(my $bmname = $dh2->read)) { 
            next if $bmname =~ /^\./;
            Log(90, "  Reading benchmark directory for '$dir', '$benchdir', '$bmname'\n");
            my $bmstarttime = Time::HiRes::time;
            my $topdir = jp ($dir, $bmname);
            if ($bmname =~ m/^(\d{3})\.(\S+)$/) {
                my ($num, $name) = ($1, $2);
                if ($seen{$name} && $num < 990) {
                    # 990 and up are for "system" benchmarks like specrand
                    # which must be run but aren't reported.
                    Log(0, "\n'$name' appeared as a benchmark name more than once, ignoring\n");
                    next;
                }
                my $specdir = jp($topdir, 'Spec');
                my $pm = jp($specdir, 'object.pm');
                my $flags_file = jp($specdir, 'flags.xml');
                if ($name =~ m/\./) {
                    Log(0, "\nBenchmark name '$name' may not contain a '.'; ignoring\n");
                } elsif (-d $specdir && -r $pm && -r $flags_file) {
                    my $objectstarttime = Time::HiRes::time;
                    # Get the version
                    my $tmpver = (::read_file(jp($topdir, 'version.txt')))[0];
		    # Get rid of whitespace
		    $tmpver =~ tr/\012\015 \011//d;
                    if (!defined($tmpver) || $tmpver eq '' || $tmpver !~ /^\d+$/) {
                        Log(0, "\nError instantiating $num.$name: version.txt file is missing or contains nonsense\n");
                        next;
                    }
                    chomp($tmpver);
                    eval "
                          package Spec::Benchmark::${name}${num};
                          \@Spec::Benchmark::${name}${num}::ISA = qw(Spec::Benchmark);
                          \$Spec::Benchmark::${name}${num}::version = $tmpver;
                          require '$pm';
                         ";
                    Log(90, sprintf("    Evaluated $pm in %8.9fs\n", Time::HiRes::time - $objectstarttime));
                    if ($@) {
                        Log(0, "\nError requiring '$pm': $@\n");
                        next;
                    }
                    $objectstarttime = Time::HiRes::time;
                    my $class="Spec::Benchmark::${name}${num}";
                    if (!$class->can('new')) {
                        Log(0, "\nNo 'new' for class '$class' in '$pm'\n");
                        next;
                    }
                    my $obj = $class->new($topdir, $config, $num, $name);
                    if (!defined($obj) || !ref($obj)) {
                        Log(0, "\nError initializing '$pm'\n");
                        next;
                    }
                    Log(90, sprintf("    Instantiated $class in %8.9fs\n", Time::HiRes::time - $objectstarttime));
                    $objectstarttime = Time::HiRes::time;
                    locate_srcalts($obj);
                    Log(90, sprintf("    Finding src.alts took %8.9fs\n", Time::HiRes::time - $objectstarttime));
                    $seen{$name}++;
                    $config->{'benchmarks'}{$bmname} = $obj;
                    Log(90, sprintf("  Setting up $name took %8.9fs\n\n", Time::HiRes::time - $bmstarttime));
                }
            } elsif ($bmname =~ /^([^\/\\:;]+)\.bset$/o) {
                my $name = $1;
                eval "
                      package Spec::Benchset::${name};
                      \@Spec::Benchset::${name}::ISA = qw(Spec::Benchset);
                      require '$topdir';
                     ";
                if ($@) {
                    Log(0, "\nError requiring benchset file '$topdir': $@\n");
                    next;
                }
                my $class="Spec::Benchset::${name}";
                if (!$class->can('new')) {
                    Log(0, "\nNo 'new' for class '$class' in '$topdir'\n");
                    next;
                }
                my $obj = $class->new($config);
                if (!defined($obj) || !ref($obj)) {
                    Log(0, "\nError initializing '$topdir'\n");
                    next;
                }
                $config->{'benchsets'}{$obj->name} = $obj;
            } elsif ($suitename =~ m/^(\d{3})\.(\S+).tar/i) {
              next;
            }
        }
        Log(90, sprintf("Setting up suite took %8.9fs\n", Time::HiRes::time - $suitestarttime));
    }
    my $error = 0;
    for my $set (keys %{$config->{'benchsets'}}) {
	my $obj = $config->{'benchsets'}{$set};
	my $ref = {};
	$config->{'benchsets'}{$set}{'benchmarks'} = $ref;
	my @benchmarks = @{$obj->{'benchmarklist'}};
	for my $bench (@benchmarks) {
	    if (!exists $config->{'benchmarks'}{$bench}) {
		Log(0, "\nBenchmark Set '$set' calls for nonexistent benchmark '$bench'\n");
		$obj->{'valid'} = 'X';
                $error++;
	    } else {
	        $ref->{$bench} = $config->{'benchmarks'}{$bench};
            }
	}
    }
    ::do_exit(1) if $error;
    $config->{'setobjs'} = [ map {$config->{'benchsets'}{$_}} keys %{$config->{'benchsets'}} ];
}

sub locate_srcalts {
    my ($bmobj) = @_;

    my $srcaltdir = jp($bmobj->{'path'}, 'src', 'src.alt');
    my $dh = new IO::Dir $srcaltdir;
    return unless defined($dh);
    while (defined(my $dir = $dh->read)) { 
	#print  "Reading '$dir', '$srcaltdir'\n";
	next if $dir eq '.' || $dir eq '..';
        next if $dir =~ /^\./o;         # src.alt names may not begin with '.'
	my $path     = jp($srcaltdir, $dir);
	my $basedir = $dir;
        my $name     = $bmobj->{'name'}.$bmobj->{'num'}.$dir;
	next if ! -d $path;
	my $pm = jp($path, 'srcalt.pm');
	if (! -r $pm) {
	    Log(0, "\nERROR: src.alt '$dir' for $bmobj->{'num'}.$bmobj->{'name'} contains no control file! Skipping...\n");
	    next;
	}
	eval "package Spec::Benchmark::srcalt::${name}; require '$pm';";
	if ($@) {
	    Log(0, "\nERROR in src.alt control file '$pm': $@\n");
	} else {
	    my $infoptr;
	    {
		no strict 'refs';
		$infoptr = ${"Spec::Benchmark::srcalt::${name}::info"};
	    }
            foreach my $member (qw(name forbench usewith filesums diffsums diffs)) {
		if (!exists $infoptr->{$member}) {
		    Log(0, "\nERROR: src.alt '$dir' for $bmobj->{'num'}.$bmobj->{'name'} has an incomplete control file; ignoring\n");
		    next;
		}
	    }
            if (ref($infoptr->{'filesums'}) ne 'HASH') {
		Log(0, "\nERROR: src.alt '$dir' for $bmobj->{'num'}.$bmobj->{'name'} has corrupt file sums; ignoring\n");
		next;
	    }
	    if ($infoptr->{'forbench'} ne $bmobj->{'num'}.'.'.$bmobj->{'name'}) {
		Log(0, "\nERROR: src.alt '$dir' for $infoptr->{'forbench'} is in $bmobj->{'num'}.$bmobj->{'name'}\'s directory; ignoring\n");
		next;
	    }
            my ($min, $max);
	    if (ref($infoptr->{'usewith'}) eq 'ARRAY') {
	        # It's a range
	        ($min, $max) = @{$infoptr->{'usewith'}};
	    } else {
	        ($min, $max) = ($infoptr->{'usewith'}, $infoptr->{'usewith'});
	    }
	    if ($::suite_version >= $min && $::suite_version <= $max) {
		$infoptr->{'path'} = $path;
		# Fix up the paths in the filesums struct
		foreach my $filepath (keys %{$infoptr->{'filesums'}}) {
		    next unless ($filepath =~ /^benchspec/);
		    $infoptr->{'filesums'}->{jp($ENV{'SPEC'}, $filepath)} =
			$infoptr->{'filesums'}->{$filepath};
		    # Neaten up
		    delete $infoptr->{'filesums'}->{$filepath};
		}
	        $bmobj->{'srcalts'}->{$infoptr->{'name'}} = $infoptr;
		Log(10, "\nFound src.alt '$infoptr->{'name'}' for $bmobj->{'num'}.$bmobj->{'name'}\n");
	    } else {
		Log(0, "\nERROR: src.alt '$infoptr->{'name'}' for $bmobj->{'num'}.$bmobj->{'name'} is not useable with this version of ${main::suite}!\n");
	    }
        }
    }
}

1;
