#
# benchset.pm
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: benchset.pm 1909 2012-10-15 18:18:52Z CloyceS $
#

package Spec::Benchset;

use strict;
use Scalar::Util qw(reftype);
use vars '@ISA';

@ISA = (qw(Spec::Config));

my $version = '$LastChangedRevision: 1909 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'benchset.pm'} = $version;

require 'benchset_common.pl';

sub report {
    my ($me, $benchobjs, $config, $mach, $ext, $size, $size_class) = @_;
    my $found_one = 0;
    my $result;
    my @bm_list = ();
    # If $config->rawconfig exists, and rawformat is set, assume that it's
    # already been properly munged, and un-munge it.
    my $rawconfig = $config->accessor_nowarn('rawconfig');
    my $txtconfig = '';
    my ($junk1, $junk2);
    if (defined($rawconfig) && $config->rawformat) {
	$rawconfig = join("\n", @{$config->rawconfig});
	$txtconfig = ::decode_decompress($rawconfig);
    } else {
	$txtconfig = $config->rawtxtconfig;
	$rawconfig = ::compress_encode($txtconfig);
    }

    # Make sure that the result gets a copy of flags text and flagsinfo from
    # the config.
    my $flags = '';
    if (exists($config->{'flags'})
        && defined($config->accessor_nowarn('flags'))) {
	$flags = ::compress_encode($config->flags);
	$flags = main::encode_base64($config->flags) if !defined($flags);
    }
    
    $result = bless { 
	'mach'        => '',
	'ext'         => '',
	'size'        => '',
	'size_class'  => '',
	'rate'        => istrue($config->rate),
	'txtconfig'   => [ split ("\n", $txtconfig, -1) ],
	'rawconfig'   => [ split ("\n", $rawconfig) ],
	'rawflags'    => [ split ("\n", $flags) ],
	'flaginfo'    => $config->accessor_nowarn('flaginfo'),
	'flagsurl'    => $config->accessor_nowarn('flagsurl'),
	'table'       => istrue($me->config->table),
	'name'        => $me->name,
	'units'       => $me->units,
	'metric'      => $me->metric,
	'mean_anyway' => istrue($me->mean_anyway),
	'tunelist'    => $me->config->tunelist,
	'basepeak'    => $config->{'basepeak'},
        'review'      => istrue($config->review),
        'baggage'     => [],
        'submit'      => 0,
        'power'       => istrue($config->power),
    }, ref($me);
    if ($::lcsuite eq 'cpu2006') {
        $result->{'base_copies'} = $config->{'copies'};
    } elsif ($::lcsuite eq 'cpuv6') {
        $result->{'base_copies'} = $config->{'copies'};
        $result->{'base_threads'} = $config->{'threads'} > 0 ? $config->{'threads'} : 1;
    } elsif ($::lcsuite eq 'mpi2007') {
        $result->{'base_ranks'} = $config->{'ranks'};
    } elsif ($::lcsuite =~ /^(omp2001|omp2012)$/) {
        $result->{'base_threads'} = $config->{'threads'} > 0 ? $config->{'threads'} : 1;
    }

    # Make a list of keys that must be dumped in the raw file.
    # Without this list, setting one of these things in the config file
    # could cause it to not be dumped in the raw file.
    $result->{'do_dump'} = [ qw(mach ext size rate name units metric
                                tunelist basepeak submit) ];
    if ($::lcsuite =~ /cpu(?:2006|v6)/) {
        push @{$result->{'do_dump'}}, 'base_copies';
        push @{$result->{'do_dump'}}, 'base_threads' if ($::lcsuite eq 'cpuv6');
    } elsif ($::lcsuite eq 'mpi2007') {
        push @{$result->{'do_dump'}}, 'base_ranks';
    } elsif ($::lcsuite =~ /^(omp2001|omp2012)$/) {
        push @{$result->{'do_dump'}}, 'base_threads';
    }

    $config = $me->config;	# This probably isn't necessary
    $result->{'refs'} = [ $result ];
    $result->{'valid'} = 'S';

    # Make sure the list of valid workloads (by class) is in the result object.
    foreach my $workload (qw(ref train test)) {
        $result->{$workload} = $me->{$workload};
    }

    $result->mach ($mach) if defined $mach;
    $result->ext  ($ext)  if defined $ext;
    # $size and $size_class should always be defined.  But just in case...
    if (defined $size) {
      $result->size($size);
    } else {
      $result->size($me->size);
    }
    if (defined $size_class) {
      $result->size_class($size_class);
    } else {
      $result->size_class($me->size_class);
    }

    # Weed out benchmarks that should not be output
    foreach my $bm (keys %{$me->benchmarks}) {
        next if exists($me->{'no_output'}->{$bm});
        push @bm_list, $bm;
        $result->{'benchmarks'}->{$bm} = $me->benchmarks->{$bm};
    }

    # Now copy benchmark information into object
    if (istrue($config->power)) {
        $config->{'max_power'} = undef;
        $config->{'min_temp'} = undef;
        $config->{'max_hum'} = undef;
    }
    for my $bench (@$benchobjs) {
	next if !$result->bench_in($bench);
	$found_one = 1;
	$result->add_results($bench, $config);
    }
    return undef unless $found_one;
    if (istrue($config->power)) {
        $result->{'max_power'} = $config->{'max_power'};
        $result->{'min_temp'} = $config->{'min_temp'};
        $result->{'max_hum'} = $config->{'max_hum'};
    }

    for my $bench (@bm_list) {
	my $bm =$me->{'benchmarks'}->{$bench};
        if (!defined($bm) || !ref($bm)) {
            # The benchmark in question was never actually instantiated.
            # Its entry should not be deleted, because the benchset _DID_
            # call for it.  So insert a bogus ref time for it; the whole
            # result will be invalid, because it was _definitely_ not run.
            $result->{'reference'}->{$bench} = 1;
        } else {
            $result->{'reference'}->{$bench} = $bm->reference;
        }
    }

    # Setting this allows us to access all settings for all benchmarks from
    # the top level.  Normally this would be a problem (for basepeak, etc),
    # but since we're only interested in the text things, it should be okay
    $config->{'refs'} = [
			 reverse ($config,
				  $config->ref_tree('',
						    ['default', $me->name, 
						     sort @bm_list],
						    ['default', @{$config->valid_tunes} ],
						    ['default', $ext],
						    ['default', $mach])) ];

    if (istrue($config->power)) {
        $result->{'hw_psu'} = $config->accessor_nowarn('hw_psu');
        $result->{'hw_psu_info'} = $config->accessor_nowarn('hw_psu_info');
    }

    # Grab the mail settings...
    $result->{'mail'} = {};
    foreach my $key (qw(mailto mailmethod mailserver mailport username
			lognum logname sendmail mail_reports)) {
	$result->{'mail'}->{$key} = $config->accessor_nowarn($key);
    }
    $result->{'mail'}->{'compress'} = istrue($config->accessor_nowarn('mailcompress'));
    $result->{'mail'}->{'runspec_argv'} = $config->accessor_nowarn('runspec_argv') || 'Command line not available';

    # If different graph settings have been specified, copy them in
    foreach my $what (qw(graph_min graph_max graph_auto)) {
      if (defined($config->accessor_nowarn($what))) {
        $result->{$what} = $config->accessor_nowarn($what);
      }
    }

    # Deal with the [hw_vendor, test_sponsor, tester] mess up front, instead of
    # making the formatters deal with it.
    my $hw_vendor_tag = 'hw_vendor';
    if ($::lcsuite eq 'mpi2007') {
        $hw_vendor_tag = 'system_vendor';
    }
    my %rewrite_fields = (); # Fields to put back in config file
    my @hw_vendor    = ::allof($config->accessor_nowarn($hw_vendor_tag));
    my @test_sponsor = ::allof($config->accessor_nowarn('test_sponsor'));
    my @tester       = ::allof($config->accessor_nowarn('tester'));
    if (   @hw_vendor > 0 && defined($hw_vendor[0])
        && (@test_sponsor <= 0 || $test_sponsor[0] =~ /^(|--)$/)) {
        if (@hw_vendor == 1) {
            $config->{'test_sponsor'} = $hw_vendor[0];
        } else {
            $config->{'test_sponsor'} = [ @hw_vendor ];
        }
        @test_sponsor = @hw_vendor;
        $rewrite_fields{'test_sponsor'} = 1;
    }
    if (   @test_sponsor > 0 && defined($test_sponsor[0])
        && (@tester <= 0 || $tester[0] =~ /^(|--)$/)) {
        if (@test_sponsor == 1) {
            $config->{'tester'} = $test_sponsor[0];
        } else {
            $config->{'tester'} = [ @test_sponsor ];
        }
        $rewrite_fields{'tester'} = 1;
    }
    if (!grep { /^peak$/o } @{$config->tunelist}) {
      $config->{'sw_peak_ptrsize'} = 'Not Applicable';
      $rewrite_fields{'sw_peak_ptrsize'} = 1;
    }

    # Copy text data into object
    my @keys = sort ::bytag $config->list_keys;

    # Figure out which nodes and interconnects are mentioned
    $result->{'mpi_items'} = {};
    foreach my $key (@keys) {
        $result->{'mpi_items'}->{$1} = [ $2, $3 ] if ($key =~ /($::mpi_desc_re)/);
    }

    if (istrue($result->power)) {

        # Add in the idle power measurements
        foreach my $item qw(power temp hum uncertainty) {
            foreach my $qty (qw(avg min max)) {
                $result->{'idle_'.$qty.'_'.$item} = $config->{'idle_'.$qty.'_'.$item};
            }
            # Humidity samples are rolled in with temperature samples, and
            # there are no uncertainty samples
            $result->{'idle_'.$item.'samples'} = $config->{$item.'samples'} unless $item =~ /^(?:hum|uncertainty)$/;
        }
        foreach my $item qw(volt amp) {
            my $tmp = $config->{'idle_'.$item.'_range'};
            $result->{'idle_'.$item.'_range'} = defined($tmp) ? [ @$tmp ] : [];
        }
        # We don't keep track of minimum uncertainty
        delete $result->{'idle_min_uncertainty'};

        # Add in the power analyzer & temp meter info
        $result->{'meterlist'} = { 'power' => [], 'temperature' => [] };
        foreach my $meterref (@{$config->powermeterlist}, @{$config->tempmeterlist}) {
            my $tag = $meterref->{'tag'};
            my $mode = lc($meterref->{'ptd_mode'});
            my $basekey = $mode.'_'.$tag;

            # This is for the benefit of power_info_munge()
            my $tmpres = { 'meterlist' => { 'power' => [], 'temperature' => [] },
                           'meters' => { $mode => { } } };
            push @{$tmpres->{'meterlist'}->{$mode}}, $tag;

            # Now get the list of fields that we should put into the result
            ::power_info_munge($tmpres);
            my @tmpfields = map { [ $_->[0] ] } @{$tmpres->{'meters'}->{$mode}->{$tag}};

            # Copy all non-mutable data from the meter object
            foreach my $key (keys %{$meterref}) {
                next if $key =~ /^(?:sock|name|responses|tag)$/;
                $result->{$basekey."_$key"} = $meterref->{$key};
            }
            # Make a nice version of the PTD version info
            $result->{$basekey.'_version'} = $meterref->{'ptd_full_version'}.' ('.$meterref->{'ptd_crc'}.'; '.$meterref->{'ptd_build_date'}.')';

            # Add fields (if they don't already exist) for related info.
            # The duplication is not a problem here... Just a little extra work
            unshift @tmpfields, [ 'hw_'.$basekey.'_label', $meterref->{'name'}   ],
                                [ 'hw_'.$basekey.'_model', $meterref->{'driver'} ];
            my %seenfields = ();
            foreach my $tref (@tmpfields) {
                my ($field, $src) = @{$tref};
                next if $seenfields{$field};
                $seenfields{$field}++;
                my $tmp = $config->accessor_nowarn($field);
                $src = $tmp if (defined($tmp) && $tmp ne '');
                $src = '--' unless defined($src);
                $result->{$field} = $src;
            }
        }
    }

    # Get all the config file indices into the result object.
    foreach my $idx (grep { /^cfidx_/ } @keys) {
	$result->{$idx} = $config->accessor($idx);
    }

    # Get the setting for sw_parallel_other into the top level
    $result->{'sw_parallel_other'} = $config->accessor_nowarn('sw_parallel_other') || '--';

    # There are some things that may be set in the config file
    # and also on the command line.  The raw file will reflect the value
    # that is actually used; the config file should be modified accordingly.

    # Single-value things (none at the moment)
    #foreach my $item () {
    #  my $text = $config->accessor_nowarn($item);
    #  $text = '' unless defined($text);
    #  my $oldtag = exists($result->{'cfidx_'.$item}) ? $item : undef;
    #  if (!::update_stored_config($result, $oldtag, $item, $text, 1, 1)) {
    #    ::Log(0, "WARNING: Could not update actual value used for \"$item\" in\n          stored config file\n");
    #  }
    #}

    # Multi-valued things
    foreach my $item (qw(flagsurl)) {
        my $aref = $config->accessor_nowarn($item);
        $aref = [] unless (reftype($aref) eq 'ARRAY');
        my @oldtags = sort grep { defined } map { if (/^cfidx_($item\d*)$/) { $1 } else { undef } } keys %{$result};

        # If there are more old items than new ones, go ahead and delete the
        # ones that won't be in the set any more.
        if (@oldtags > @{$aref}) {
            my @deltags = splice(@oldtags, @{$aref});
            foreach my $deltag (@deltags) {
                if (!::update_stored_config($result, $deltag, undef, undef, 1, 1)) {
                  ::Log(0, "WARNING: Could not remove \"$deltag\" in stored config file\n");
                }
            }
        }

        # Now modify the ones that are left.  This is done twice in order to
        # avoid problems with clashing names.
        my $curridx = 0;
        my @newtags = ();
        foreach my $val (@{$aref}) {
            my $oldtag = shift(@oldtags);
            my $newtag = sprintf "$item%03d", $curridx++;
            $newtag =~ s/(.)/chr(ord($1) | 0x80)/goe;
            if (!::update_stored_config($result, $oldtag, $newtag, $val, 1, 1)) {
                ::Log(0, "WARNING: Could not update actual value used for \"$oldtag\" in\n          stored config file\n");
            } else {
                push @newtags, [ $newtag, $val ];
            }
        }
        foreach my $tagref (@newtags) {
            my ($tag, $val) = @{$tagref};
            my $oldtag = $tag;
            $tag =~ s/(.)/chr(ord($1) & 0x7f)/goe;
            if (!::update_stored_config($result, $oldtag, $tag, $val, 1, 1)) {
                ::Log(0, "WARNING: Could not update temporary tag name for \"$tag\" in\n          stored config file\n");
            }
        }
    }

    my @systems = ('');
    push @systems, keys %{$result->{'mpi_items'}} if ($::lcsuite eq 'mpi2007');
    foreach my $system (@systems) {
        my @tags = ();
        if ($system eq '') {
            if ($::lcsuite ne 'mpi2007') {
                @tags = (
                    # These are all the things that have a field on the report
                    @::hardware_info, @::software_info,
                    (istrue($me->power) ? @::power_info : ()),
                    @::extra_info,
                    map { [ $_ ] } qw(hw_nchips hw_ncores hw_ncoresperchip hw_nthreadspercore));
            } else {
                my $tmp_hw_info = ::fixup_subparts($config, $::mpi_info{'hardware'}, $system);
                my $tmp_sw_info = ::fixup_subparts($config, $::mpi_info{'software'}, $system);
                @tags = (@{$tmp_hw_info},
                         @{$tmp_sw_info},
                         (istrue($me->power) ? @::power_info : ()),
                         @::extra_info);
            }
        } else {
            my ($type, $which) = @{$result->{'mpi_items'}->{$system}};
            my $tmp_tags = ::fixup_subparts($config,
                   [ map { [ $system.$_->[0], $_->[1], $_->[2] ] } @{$::mpi_info{$type}} ],
                   $system);
            @tags = @{$tmp_tags};
        }
        for my $tagref (@tags) {
            my $tag = $tagref->[0];
            next if exists($::generated_fields{$tag});      # Already done
            next if $tag =~ /^(?:idle|power|temperature)_/; # Skip PTD stuff
            my @data = ();
            my $tagre = qr/^$tag\d*$/;
            for my $key (grep { m/$tagre/ } @keys) {
                my $index = $result->{'cfidx_'.$key} if exists($result->{'cfidx_'.$key});
                my $val = $config->accessor($key);
                if ($config->info_wrap_columns == 0 ||
                    length($val) <= $config->info_wrap_columns) {
                    push @data, [ $val, $index, $key ];
                } else {
                    ::Log(0, "NOTICE: $key is longer than ".$config->info_wrap_columns." characters and will be split\n");
                    my @newlines = ::wrap_lines([$val], $config->info_wrap_columns);
                    push @data, [ shift(@newlines), $index, $key, 1 ];
                    foreach my $line (@newlines) {
                        push @data, [ $line, (defined($index) ? $index+1 : undef), undef, 1 ];
                    }
                }
            }
            @data = ([ exists($::empty_fields{$tag}) ? '' : '--', undef, $tag, 0 ]) unless @data;
            if (   @data > 1
                || $data[0]->[2] ne $tag
                || exists($rewrite_fields{$tag})
            ) {
                $result->{$tag} = [ ];
                # Go through @data twice.
                my @redo = ();
                # This first pass is to rename/change lines that are pre-existing
                for (my $i = $#data; $i >= 0; $i--) {
                    my ($text, $index, $key, $doupdate) = @{$data[$i]};
                    if (@data > 1) {
                        $result->{$tag}->[$i] = $text;
                    } else {
                        $result->{$tag} = $text;
                    }
                    if (defined($key) && $key ne '') {
                        my $newtag;
                        if (@data > 1) {
                            # There's more than one line, so newtag should have an
                            # index.
                            $newtag = sprintf '%s%03d', $tag, $i;
                        } else {
                            # There's only one line, but it was numbered in the
                            # config file, so we'll be rewriting it to its
                            # non-indexed value.
                            $newtag = $tag;
                        }
                        if ($key ne $newtag &&
                            exists($result->{'cfidx_'.$newtag})) {
                          # Oops... that spot is taken.  Tweak the new tag a bit
                          # to avoid the clash, and put it on the list for
                          # another pass later.
                          push @redo, [ $newtag, $text ];
                          $newtag =~ s/(.)/chr(ord($1) | 0x80)/goe;
                        }
                        $result->{'cfidx_'.$key} = $index if defined($index);
                        my $oldtag = $key;
                        if (   exists($rewrite_fields{$tag})
                            && !defined($index)
                        ) {
                          $oldtag = undef;      # Add the field
                        }
                        if (!::update_stored_config($result, $oldtag, $newtag, $text, $doupdate, 1)) {
                            ::Log(0, "ERROR: Could not update tag name in stored config file for $tag\n");
                        }
                    }
                }
                # This is not a second pass through @data; some tags may need to
                # be fixed up, if the config file author crafted her config file
                # just right.  See ConfigRewritingWarnings for details.
                if (@redo) {
                  foreach my $redoref (@redo) {
                    next unless (::reftype($redoref) eq 'ARRAY');
                    my ($newtag, $text) = @{$redoref};
                    my $oldtag = $newtag;
                    $oldtag =~ s/(.)/chr(ord($1) | 0x80)/goe;
                    if (!::update_stored_config($result, $oldtag, $newtag, $text, 0, 1)) {
                        ::Log(0, "ERROR: Could not update tag name in stored config file for $tag\n");
                    }
                  }
                }
                # This second pass is to add lines that are newly generated
                for (my $i = $#data; $i >= 0; $i--) {
                    my ($text, $index, $key, $doupdate) = @{$data[$i]};
                    if ((defined($doupdate) && $doupdate) &&
                        (!defined($key) || $key eq '')) {
                        # See if there's an index for the next or previous
                        # field and use it
                        my $tmpkey;
                        if (!defined($index) && $i > 0) {
                            $tmpkey = sprintf '%s%03d', $tag, $i - 1;
                            $index = ($result->{'cfidx_'.$tmpkey} + 1) if exists($result->{'cfidx_'.$tmpkey});
                        }
                        if (!defined($index)) {
                            $tmpkey = sprintf '%s%03d', $tag, $i + 1;
                            $index = ($result->{'cfidx_'.$tmpkey} - 1) if exists($result->{'cfidx_'.$tmpkey});
                        }
                        my $newtag = sprintf '%s%03d', $tag, $i;
                        $newtag .= sprintf ':%d', $index if defined($index);
                        if (!::update_stored_config($result, undef, $newtag, $text, $doupdate, 1)) {
                            ::Log(0, "ERROR: Could not add new line in stored config file for $tag\n");
                        }
                    }
                }
            } else {
                my ($text, $index) = @{$data[0]};
                $result->{$tag} = $text;
                $result->{'cfidx_'.$tag} = $index if (defined($index) && $index)
            }
        }
    }

    # Notes are a little special.

    # The array refs initially put into $result->{notes*} have three elements:
    # 0. Whether the text line should be edited (1) or just the tag (0)
    # 1. The original tag
    # 2. The note
    # The tag can be undef, in which case a new one needs to be generated
    # and a line inserted into the config file.
    my $safe;
    my %seen_tags = ();
    my %seen_notes = ();
    foreach my $sectionref (@::notes_info) {
        next unless ref($sectionref) eq 'ARRAY';
        next if ($sectionref->[0] eq 'notes_submit' && !$result->{'submit'});
        my $note_tag;
        my $notere   = $sectionref->[2];
        foreach my $tag (sort ::bytag @keys) {
            next unless $tag =~ m/$notere/;
            # Avoid making two references to a notes line from a pre-defined
            # section (like "notes_plat" or "notes_submit").
            # Otherwise the config file rewriting will fail with scary messages,
            # and the note will show up both in its proper section as well as
            # the general section.
            next if exists($seen_notes{$tag}); # Do not double-process notes
            $note_tag = $1;
            $seen_notes{$tag}->{$note_tag}++;
            my ($key, $idx) = ($2, $3 + 0);
            $seen_tags{$note_tag}++;
            $result->{$note_tag} = {} unless exists($result->{$note_tag}) && (reftype($result->{$note_tag}) eq 'HASH');
            my $val = $config->accessor($tag);
            if (istrue($config->expand_notes)) {
                ($val, $safe) = ::command_expand($val, $config, 'safe' => $safe);
            }
            $result->{$note_tag}->{$key}->[$idx] = [ 0, $tag, $val ];
        }
    }

    # Now squeeze undefs from all the hashes
    foreach my $note_tag (keys %seen_tags) {
        foreach my $key (keys %{$result->{$note_tag}}) {
            my $notesref = $result->{$note_tag}->{$key};
            if (ref($notesref) eq 'ARRAY') {
                ::squeeze_undef($notesref);
            } else {
                # This should never happen
                delete $result->{$note_tag}->{$key};
                next;
            }

            # Run through the notes and make sure that none are multi-line.
            for (my $i = 0; $i < @{$notesref}; $i++) {
                my (undef, $oldtag, $text) = @{$notesref->[$i]};
                if ($text =~ /[\r\n]/) {
                    my @lines = split(/(?:\r\n|\n)/, $text, -1);
                    my $cfline = $result->{'cfidx_'.$oldtag};
                    my @newlines = ([ 1, $oldtag, shift(@lines) ]);
                    my $blockquote = 0;
                    my $endtag = '';
                    if (defined($cfline)) {
                        # Check to see if it's the start of a block quote.
                        # If it is, two more lines will have to be hacked
                        # off after the loop.
                        if ($result->{'txtconfig'}->[$cfline] =~ /^\s*$oldtag\s*=\s*<<(\S+)\s*$/) {
                            $endtag = $1;
                            $blockquote = 1;
                        }
                    }
                    # Make an array where each position indicates whether a
                    # particular config file line has an item associated
                    # with it.  It's almost a reverse mapping of the cfidx_*
                    # values.
                    my $used_cflines = [];
                    map { $used_cflines->[$_] = 1 } map { $result->{$_} } grep { /cfidx_/ } keys %{$result};
                    foreach my $newline (@lines) {
                        push @newlines, [ 0, undef, $newline ];
                        # If this newly-split line is indeed a part of the
                        # config file, then it needs to be excised.
                        if (defined($cfline) &&
                            ($blockquote ||
                             ($result->{'txtconfig'}->[$cfline + 1] =~ $newline
                              && !defined($used_cflines->[$cfline + 1])))) {
                            # Remove the extra line from the config file
                            splice @{$result->{'txtconfig'}}, $cfline + 1, 1;
                            # Adjust the indices
                            ::shift_indices($result, $cfline + 1, -1);
                            $used_cflines = [];
                            map { $used_cflines->[$_] = 1 } map { $result->{$_} } grep { /cfidx_/ } keys %{$result};
                        }
                    }
                    if ($blockquote) {
                        # Hack off two more lines @ $cfline.  Check to make
                        # sure that the second of the two contains the end tag.
                        if ($result->{'txtconfig'}->[$cfline + 2] ne $endtag) {
                            ::Log(0, "WARNING: Block quote end tag \"$endtag\" not found while rewriting\n  config file lines.  Please report this bug to ${main::lcsuite}support\@spec.org!\n");
                        } else {
                            splice @{$result->{'txtconfig'}}, $cfline + 1, 2;
                            ::shift_indices($result, $cfline + 1, -2);
                        }
                    }
                    splice @{$notesref}, $i, 1, @newlines;
                }
            }

            if ($config->notes_wrap_columns > 0) {
                # So that it's possible to fix up the stored config file and the
                # associated indices, wrap the notes lines one by one
                my @newnotes = ();
                foreach my $noteref (@{$notesref}) {
                    my ($edit, $tag, $note) = @$noteref;
                    if (length($note) < $config->notes_wrap_columns) {
                        # It obviously won't be wrapped, right?
                        push @newnotes, $noteref;
                    } else {
                        my @repl;
                        ($note, undef) = ::protect_notes_links($note, \@repl);
                        my @newlines = ::wrap_lines([ $note ],
                                                    $config->notes_wrap_columns,
                                                    $config->notes_wrap_indent);
                        @newlines = map { ::unprotect_notes_links($_, \@repl) } @newlines;
                        if (@newlines > 1) {
                            # A line was wrapped
                            push @newnotes, [ 1, $tag, shift(@newlines) ];
                            push @newnotes, map { [ 0, undef, $_ ] } @newlines;
                        } else {
                            push @newnotes, $noteref;
                        }
                    }
                }
                @{$notesref} = @newnotes;
            }
        }
    }

    # This needs to be present.
    $result->{'notes'}->{''} = [] unless (reftype($result->{'notes'}->{''}) eq 'ARRAY');

    # If there are saved notes from the build, insert them now.
    if (@{$result->{'baggage'}} > 0) {
        foreach my $note (@{$result->{'baggage'}}) {
            unshift @{$result->{'notes'}->{''}}, map { [ 0, undef, $_ ] } split(/(?:\r\n|\n)+/, $note), '';
        }
    }
    delete $result->{'baggage'};

    # Note the settings for environment variables set via preENV_
    if (istrue($config->note_preenv)) {
        my @pre_env = sort map { s/^preENV_//; $_ } grep { /^preENV_/ } keys %{$config};

        my $startmsg = 'Environment variables set by runspec before the start of the run:';
        # Find out if any previous instances of this logging have happened
        my $startidx = find_note($result->{'notes'}->{''}, $startmsg);
        if (!defined($startidx)) {
            # Easy; just add them all
            unshift @{$result->{'notes'}->{''}},
                      (
                       [ 0, undef, $startmsg ],
                       (map { [ 0, undef, "$_ = \"".$config->accessor_nowarn("preENV_$_").'"' ] } @pre_env),
                       [ 0, undef, '' ]
                      );
        } else {
            # Go through the list and replace notes that were previously
            # present.  New ones will be inserted right after $startidx
            foreach my $pre_env (reverse @pre_env) {
                my $newnote = "$pre_env = \"".$config->accessor_nowarn("preENV_${pre_env}").'"';
                my $idx = find_note($result->{'notes'}->{''},
                                    qr/^${pre_env} = ".*"$/, $startidx, qr/^$/);
                if (defined($idx)) {
                    # Easy -- just replace it
                    $result->{'notes'}->{''}->[$idx]->[2] = $newnote;
                } else {
                    # Also easy -- ease it in after the start
                    splice @{$result->{'notes'}->{''}}, $startidx + 1, 0, [ 0, undef, $newnote ];
                }
            }
        }
    }

    # Renumber the notes _now_ so that the config file (and the indices) can
    # be updated.
    ::renumber_notes($result, 3, 0);

    # Blow away the old stored config and replace it with txtconfig
    $result->{'rawconfig'} = [ split(/\n/, ::compress_encode(join("\n", @{$result->{'txtconfig'}}))) ];
    if (exists($result->{'orig_raw_config'}) && !exists($result->{'origconfig'})) {
        my $diff = $#{$result->{'orig_raw_config'}} != $#{$result->{'txtconfig'}};
        for(my $i = 0; $i < $#{$result->{'txtconfig'}} && $diff == 0; $i++) {
            $diff = ($result->{'txtconfig'}->[$i] ne $result->{'orig_raw_config'}->[$i]);
        }
        if ($diff) {
            $result->{'origconfig'} = [ split(/\n/, ::compress_encode(join("\n", @{$result->{'orig_raw_config'}}))) ];
        } else {
            # orig_raw_config and txtconfig are the same, so don't save two
            # copies.
            delete $result->{'orig_raw_config'};
            delete $result->{'orig_raw_good'};
        }
    } else {
        # Nuke the original config if it's the same as the current
        delete $result->{'origconfig'} if $result->{'origconfig'} eq $result->{'txtconfig'};
    }
    delete $result->{'txtconfig'};

    # Reconstitute the compile-time options for the convenience of any
    # formatters that might wish to make use of it.
    for my $bench (keys %{$result->{'compile_options'}}) {
	for my $tune (keys %{$result->{'compile_options'}->{$bench}}) {
	    my $rawopts = $result->{'compile_options'}->{$bench}->{$tune};
	    next unless ($rawopts ne ''); # Skip empty ones
	    my $compopts = ::decode_decompress($rawopts);
	    $rawopts = $compopts unless ($@ || !defined($compopts));
	    $result->{'compile_options'}->{$bench}->{$tune} = $rawopts;
	}
    }

    # Break up the MPI-specific system descriptions for the formatters
    foreach my $key (keys %{$result}) {
        next unless ($key =~ m/$::mpi_desc_re(.+)/);
        my ($type, $tag, $item) = ($1, $2, $3);
        $result->{$type}->{$tag}->{$item} = $result->{$key};
    }

    $result->{'basemean'} = 'Not Run';
    $result->{'baseenergymean'} = '--';
    $result->{'peakmean'} = 'Not Run';
    $result->{'peakenergymean'} = '--';
    my $peakseen = 0;
    if (grep { /^peak$/o } @{$config->tunelist}) {
      $peakseen = 1;
      # Munge up the results if basepeak is set, and peak was selected to run
      # If global basepeak is 1, we do wholesale base->peak substitution.
      # If global basepeak is 2, we do per-benchmark lowest median selection
      if ($result->{'basepeak'} == 1) {
	::basepeak_munge($result);
      } elsif ($result->{'basepeak'} == 2) {
	my @bp_bench = ();
	for my $bench (keys %{$result->benchmarks}) {
	    next unless istrue($me->{'benchmarks'}->{$bench}->{'basepeak'});
	    push @bp_bench, $bench;
	}
	::basepeak_munge($result, 0, @bp_bench);
      }
      if ($result->rate) {
          ($result->{'peakmean'}, $result->{'peakenergymean'}) = $result->calc_mean_rate('peak');
      } else {
          ($result->{'peakmean'}, $result->{'peakenergymean'}) = $result->calc_mean_speed('peak');
      }
    }
    if (grep { /^base$/o } @{$config->tunelist}) {
      if ($result->rate) {
          ($result->{'basemean'}, $result->{'baseenergymean'}) = $result->calc_mean_rate('base');
      } else {
          ($result->{'basemean'}, $result->{'baseenergymean'}) = $result->calc_mean_speed('base');
      }
    }
    push @{$result->{'do_dump'}}, qw(basemean peakmean);

    # Generate the generated fields
    if ($::lcsuite eq 'mpi2007') {
        ::generate_mpi_totals($result, $config);
        ::mpi_min_max_ranks($result);
    } else {
        if ($::lcsuite ne 'cpu2006') {
            ::mpi_min_max_ranks($result);
        }
        # Assemble the hw_ncpu field from the various components
        $result->{'hw_ncpu'} = ::assemble_cpu_description($config);
    }
    # Just copy test_date in
    $result->{'test_date'} = $config->{'test_date'};


    # Check for some basic errors
    $result->add_error("'reportable' flag not set during run") if !istrue($config->reportable);

    my $saw_base = 0;
    for my $tune (@{$config->tunelist}) {
	$saw_base++ if ($tune eq 'base');
	for my $bench ($result->insufficient_data($tune)) {
	    $result->add_error("$bench ($tune) did not have enough runs!\n");
	}
	for my $bench ($result->invalid_results($tune)) {
	    $result->add_error("$bench ($tune) had invalid runs!\n");
	}
    }
    if (!$saw_base) {
	$result->add_error("No 'base' runs!  Base measurement required!\n");
    }
    if ($result->size ne $result->ref) {
	$result->add_error("Input set must be '".$result->ref."' for a valid run (set to '".$result->size."' for this run)\n");
    }

    return $result;
}

sub find_note {
    my ($notes, $re, $start, $termre) = @_;
    $start = 0 unless defined($start);

    if (reftype($notes) eq 'ARRAY') {
        $re = qr/^${re}$/ unless (ref($re) eq 'Regexp');
        $termre = qr/^${termre}$/ unless (ref($termre) eq 'Regexp');
        for(my $i = $start; $i <= $#{$notes}; $i++) {
            return $i if $notes->[$i]->[2] =~ /$re/;
            last if $notes->[$i]->[2] =~ /$termre/;
        }
    }
    return undef;
}

1;
