#
#  asc.pl - produces ASCII output
#  Copyright 1999-2012 Standard Performance Evaluation Corporation
#   All Rights Reserved
#
#  Authors:  Christopher Chan-Nui
#            Cloyce D. Spradling
#
# $Id: asc.pl 1869 2012-10-02 22:06:45Z CloyceS $

use strict;
use Scalar::Util qw(reftype);
require 'util.pl';
require 'flagutils.pl';

use vars qw($name $extension $synonyms);

$name      = 'ASCII';
$extension = 'txt';
$synonyms  = { map { lc($_) => 1 } ($name, $extension, qw(text asc)) };
my $asc_version = '$LastChangedRevision: 1869 $ '; # Make emacs happier
$asc_version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$Spec::Format::asc::part_of_all = 1;

$::tools_versions{'asc.pl'} = $asc_version;

my $debug = 0; #xff;
my %trademarks_done = ();
my %code2mark = ( 'r' => '(R)',
                  't' => '(TM)',
                  's' => '(SM)',
                );

sub format {
    my($me, $r, $fn) = @_;
    my (@output, @errors);
    my (%seen, $temp, $bench, $name, @values, @errmsg);
    my @nc = ::allof($r->{'nc'});
    $r->{'table'} = 0 if (@nc);
    my $invalid = ($r->{'invalid'} ||
		   ((reftype($r->{'errors'}) eq 'ARRAY') && @{$r->{'errors'}}));
    %trademarks_done = ();
    if ($invalid) {
	push (@errors, '#' x 78);
	push (@errors, sprintf ("# %-74s #", '  ' . 'INVALID RUN -- ' x 4 . 'INVALID RUN'));
	push (@errors, sprintf ("# %-74s #", ''));

	for ($r->errors) {
	    push (@errors, sprintf ("# %-74s #", $_));
	}

	push (@errors, sprintf ("# %-74s #", ''));
	push (@errors, sprintf ("# %-74s #", '  ' . 'INVALID RUN -- ' x 4 . 'INVALID RUN'));
	push (@errors, '#' x 78);
    }

    # Collect (possibly multi-line) info
    my %id_map = ($::lcsuite eq 'mpi2007') ?
                    (
                      'vendor' => 'system_vendor',
                      'model'  => 'system_name',
                    ) :
                    (
                      'vendor' => 'hw_vendor',
                      'model'  => 'hw_model',
                    );
    my @hw_vendor    = ::allof($r->accessor_nowarn($id_map{'vendor'}));
    my @hw_model     = ::allof($r->accessor_nowarn($id_map{'model'}));
    my @license_num  = ::allof($r->accessor_nowarn('license_num'));
    my @test_date    = ::allof($r->accessor_nowarn('test_date'));
    my @hw_avail     = ::allof($r->accessor_nowarn('hw_avail'));
    my @sw_avail     = ::allof($r->accessor_nowarn('sw_avail'));
    my @tester       = ::allof($r->accessor_nowarn('tester'));
    my @test_sponsor = ::allof($r->accessor_nowarn('test_sponsor'));

    my $header_string = 'SPEC ' . $r->metric .  ' Summary';
    push @output, [ fixup_trademarks($header_string), 'center' => 1 ];
    if (@hw_vendor > 1 || @hw_model > 1) {
	push @output, map { [ $_, 'center' => 1 ] } @hw_vendor;
	push @output, map { [ $_, 'center' => 1 ] } @hw_model;
    } else {
        push @output, [ $hw_vendor[0].' '.$hw_model[0], 'center' => 1 ];
    }
    # Print the test sponsor close to the hardware vendor if
    # they're not the same
    if (join(' ', @hw_vendor) ne join(' ', @test_sponsor)) {
        my @tmp = @test_sponsor;
        push @output, [ 'Test Sponsor: '.shift(@tmp), 'center' => 1 ];
        while (@tmp) {
            push @output, [ '              '.shift(@tmp), 'center' => 1 ];
        }
    }
    push @output, [ $r->datestr, 'center' => 1 ];
    push (@output, '');

    # Mash things up so that they don't look like the other results, but
    # so that the dates match up.
    # License number and test date
    my $license_label = $::suite.' License:';
    my $max_license_len = length($license_label) - 54;
    push @output, [ sprintf('%s %*s  Test date: %-8s',
                            $license_label, $max_license_len, shift(@license_num), shift(@test_date)),
                    'center' => 1 ];
    while (@license_num || @test_date) {
        push @output, [ sprintf('%*s %*s             %-8s',
                                length($license_label), ' ', $max_license_len, shift(@license_num), shift(@test_date)),
                        'center' => 1 ]
    }

    # Test sponsor and hardware availability
    push @output, [ sprintf('Test sponsor: %-29s  Hardware availability: %-8s',
                            shift(@test_sponsor), shift(@hw_avail)),
                    'center' => 1 ];
    while (@test_sponsor || @hw_avail) {
        push @output, [ sprintf('              %-29s                         %-8s',
                                shift(@test_sponsor), shift(@hw_avail)),
                        'center' => 1 ];
    }

    # Tester and software availability
    push @output, [ sprintf('Tested by:    %-29s  Software availability: %-8s',
                            shift(@tester), shift(@sw_avail)),
                    'center' => 1 ];
    while (@tester || @sw_avail) {
        push @output, [ sprintf('              %-29s                         %-8s',
                                shift(@tester), shift(@sw_avail)),
                        'center' => 1 ];
    }

    push @output, '';

    # Note the reason for NC, NA, or CD (if any).
    if (@nc) {
	push @output, '', [ '-', 'divider' => 1 ], '';
	push @output, map { [ $_, 'center' => 1 ] } @nc;
	push @output, '', [ '-', 'divider' => 1 ], '', '';
    }

    push @output, screen_format($me, $r, $fn, 1, $invalid, \@nc);

    if ($::lcsuite ne 'mpi2007') {
        push @output, format_info('HARDWARE', [ $r->hardware ]);
        push @output, format_info('SOFTWARE', [ $r->software ]);
        push @output, dump_power($r, $r->power_info);
    } else {
        # MPI is very very special

        # The "benchmark details"
        push @output, format_info('BENCHMARK DETAILS',
                                  [ $r->info_format($::mpi_info{'hardware'}),
                                    $r->info_format($::mpi_info{'software'}),
                                  ]);
        push @output, dump_power($r, $r->info_format($::mpi_info{'power'}));

        # System descriptions
        foreach my $item (qw(node interconnect)) {
            next unless exists($r->{$item}) && (reftype($r->{$item}) eq 'HASH');
            my $iref = $r->{$item};

            # Get a list of things; interconnects are ordered primarily by
            # 'order' and secondarily by 'label' (lexically).  Nodes are the
            # same, but the most primary key is whether or not purpose contains
            # "compute".
            my @itemlist;
            if ($item eq 'node') {
                @itemlist = sort {
                     $iref->{$a}->{'purpose'} !~ /compute/i <=> $iref->{$b}->{'purpose'} !~ /compute/i ||
                     $iref->{$a}->{'order'} <=> $iref->{$b}->{'order'} ||
                     $iref->{$a}->{'label'} cmp $iref->{$b}->{'label'}
                                     } keys %{$iref};
            } else {
                @itemlist = sort {
                     $iref->{$a}->{'order'} <=> $iref->{$b}->{'order'} ||
                     $iref->{$a}->{'label'} cmp $iref->{$b}->{'label'}
                                     } keys %{$iref};
            }

            foreach my $system (@itemlist) {
                push @output, '';
                my $label = ucfirst($item).' Description: '.$iref->{$system}->{'label'};
                push @output, [ $label, 'center' => 1 ],
                              [ '=' x length($label), 'center' => 1 ];

                my ($hw_info, $sw_info) = ::mpi_info_munge($r, $item, $system);

                push @output, format_info('HARDWARE', [ $r->info_format($hw_info) ]);
                push @output, format_info('SOFTWARE', [ $r->info_format($sw_info) ]);

                # Do the notes for this thing...
                my @notes = @{$r->notes("${item}_${system}_")};
                push @output, '';
                foreach my $sectionref (@notes) {
                    my ($section, $notesref) = @{$sectionref};
                    next unless (reftype($notesref) eq 'ARRAY');
                    push @output, '', [ $section, 'center' => 1 ],
                                      [ '-' x length($section), 'center' => 1 ];
                    push @output, munge_links(map { '    '.$_ } @{$notesref});
                }
            }
        }
    }

    # Do the notes
    my @notes = @{$r->notes};
    push @output, '';
    foreach my $sectionref (@notes) {
        my ($section, $notesref) = @{$sectionref};
        next unless (reftype($notesref) eq 'ARRAY');
        push @output, '', [ $section, 'center' => 1 ],
                          [ '-' x length($section), 'center' => 1 ];
        push @output, munge_links(map { '    '.$_ } @{$notesref});
    }

    # These will be handy for the flags section
    my $rf = $r->{'reduced_flags'};
    return undef unless (reftype($rf) eq 'HASH');
    my @benches = sort keys %{$rf->{'benchlist'}};
    my @tunes = sort keys %{$rf->{'tunelist'}};
    my @classes = sort keys %{$rf->{'classlist'}};

    # Do the unknown and forbidden flags; they are uncollapsed, because
    # repetition is a form of emphasis.
    my $maxtitle = 0;
    foreach my $class (qw(forbidden unknown)) {
	next unless ::check_elem(undef, $rf, 'stringlist', $class);
        # Flags of the class exist for at least one benchmark, so
        # make lists of them.  They'll be formatted and output later.
	my $maxtitle = $rf->{'maxbench'} + 3; # 2 = ' ' + ': '
        my $classref = $rf->{'stringlist'}->{$class};
        for my $tune (sort ::bytune @tunes) {
          my $title_printed = 0;
          my $title = ucfirst($tune).' '.ucfirst($class).' Flags';
          for my $bench (sort keys %{$classref}) {
	    my $printed = 0;
            next unless ::check_elem('ARRAY', $classref, $bench, $tune);
            if (!$title_printed) {
                push @output, '', [ $title, 'center' => 1 ],
                                  [ '-' x length($title), 'center' => 1 ];
                $title_printed = 1;
            }
            push @output, dump_lines(" $bench: ", $maxtitle, $classref->{$bench}->{$tune}), '';
	  }
	}
    }

    # Do all the other flags in a way that aggregates as much as possible.
    # Well, maybe.  Sometimes they're a LITTLE more expanded than they could
    # be.

    # First, figure out which form we'll use.  Will it be 0ld sk00l
    # Compiler (merged)
    # Portability (merged)
    # Base Optimization   -+- Maybe merged
    # Peak Optimization   -+
    # Other (merged)
    # ?
    # Or will it be the new style
    # Base Compiler Invocation
    # Base Portability Flags
    # Base Optimization
    # Base Other Flags
    # Peak Compiler Invocation (maybe with a back-ref to base)
    # Peak Portability Flags (maybe with a back-ref to base)
    # Peak Optimization (maybe with a back-ref to base)
    # Peak Other (maybe with a back-ref to base)
    # ?
    my $section_order = 1; # 0ld Sk00l by default
    foreach my $class (qw(compiler portability other)) {
        next unless exists $rf->{'allmatch'}->{$class};
        $section_order = $rf->{'allmatch'}->{$class};
        last unless $section_order;
    }
    # If any of the above sections don't match for all languages across all
    # tuning levels, we'll go to the "new style" order.

    my %class2title = ( 'compiler' => 'Compiler Invocation',
                        'portability' => 'Portability Flags',
                        'optimization' => 'Optimization Flags',
                        'other' => 'Other Flags' );
    my $onetune = $tunes[0];
    foreach my $tune (@tunes) {
        foreach my $class (qw(compiler portability optimization other)) {
            # Skip this tuning level pass if we're doing the old order, and EITHER
            # 1. it's the first trip through and the class is 'other'
            # or
            # 2. it's the second trip through and the class is 'compiler' or 'portability'
            # or
            # 3. it's the second trip through, the class is 'optimization', and allmatch is set
            # This is done so that the merged "other" section can come after optimization
            next if ($section_order == 1 &&
                     (($tune eq $onetune && $class eq 'other') ||
                     ($tune ne $onetune && ($class eq 'compiler' || $class eq 'portability')) ||
                     ($tune ne $onetune && $class eq 'optimization' && $rf->{'allmatch'}->{$class} == 1)));
            my $mismatch = 0;
            my $printed_title = 0;
            my %langstodo = map { $_ => 1 } keys %{$rf->{'langlist'}};
            my %donebench = ();
            my $title = $class2title{$class};

            # Easy case first -- if we're doing new section order and allmatch
            # for this class is set and this isn't the base tuning, just
            # output the "Same as ..." message
            if ($section_order == 0 &&
                exists($rf->{'allmatch'}->{$class}) &&
                $rf->{'allmatch'}->{$class} == 1 &&
                $tune ne $onetune) {
                $title = ucfirst($tune).' '.$title;
                push @output, '', [ $title, 'center' => 1 ],
                                  [ '-' x length($title), 'center' => 1 ];
                push @output, 'Same as '.ucfirst($onetune).' '.$class2title{$class},'';
                next;
            }

            # Go through the langs and print the ones that match.
            foreach my $lang (sort ::bylang keys %langstodo) {
                last if $class eq 'portability'; # Portability is by benchmark
                my $printed_lang = 0;

                # Completely merged sections are only output for 0ld sk00l order
                if ($section_order == 1) {
                    # First dump all class flags that are common across all tuning levels
                    if ($rf->{'allmatch'}->{$class} == 1 &&
                        ::check_elem('HASH', $rf, 'langmatch', $class, 'alltune') &&
                        ::check_elem('HASH', $rf, 'bylang', 'stringlist', $class, $onetune)) {
                        if (exists($rf->{'langmatch'}->{$class}->{'alltune'}->{$lang}) &&
                            $rf->{'langmatch'}->{$class}->{'alltune'}->{$lang} &&
                            # There might _not_ be an entry for a particular language if, for
                            # the same flag (like -DSPEC_WINDOWS) one benchmark calls
                            # it portability and another calls it mandatory.  This is
                            # incorrect, but it's no fault of the user.
                            ::check_elem('ARRAY', $rf, 'bylang', 'stringlist', $class, $onetune, $lang) &&
                            @{$rf->{'bylang'}->{'stringlist'}->{$class}->{$onetune}->{$lang}}) {
                            if (!$printed_title) {
                                push @output, '', [ $class2title{$class}, 'center' => 1 ],
                                                  [ '-' x length($class2title{$class}), 'center' => 1 ];
                                $printed_title = 1;
                            }
                            my @strings = ();
                            my $flags = $rf->{'bylang'}->{'flaglist'}->{$class}->{$onetune}->{$lang};
                            my $strings = $rf->{'bylang'}->{'stringlist'}->{$class}->{$onetune}->{$lang};
                            for(my $i = 0; $i < @{$flags}; $i++) {
                                next unless (istrue($flags->[$i]->[2]->{'display'}) || $r->{'review'});
                                push @strings, $strings->[$i];
                            }
                            my $langtitle = $rf->{'var2desc'}->{$lang};
                            if ($rf->{'langmatch'}->{$class}->{$onetune}->{$lang} == 2) {
                                $langtitle .= ' (except as noted below)';
                            }
                            push @output, dump_lines($langtitle.': ', 5, \@strings, { 'title_alone' => 1 }), '';
                            $printed_lang = 1;
                            delete $langstodo{$lang};
                            if (::check_elem(undef, $rf, 'bylang', 'mismatch', $class, $onetune, $lang)) {
                                $mismatch += $rf->{'bylang'}->{'mismatch'}->{$class}->{$onetune}->{$lang};
                            }
                        }
                    }

                    # Do the benchmarks of $lang that matched across tuning levels
                    if ($rf->{'allmatch'}->{$class} == 1 &&
                        ::check_elem('HASH', $rf, 'stringlist', $class)) {
                        my $classref = $rf->{'stringlist'}->{$class};
                        foreach my $bench (sort keys %{$classref}) {
                            next unless # the following six conditions are true:
                               (
                                $rf->{'langs'}->{$bench}->{$onetune} eq $lang &&
                                ::check_elem(undef, $rf, 'benchmatch', $class, $bench, 'alltune') &&
                                $rf->{'benchmatch'}->{$class}->{$bench}->{'alltune'} &&
                                ::check_elem('ARRAY', $rf, 'flaglist', $class, $bench, $onetune) &&
                                (reftype($rf->{'flaglist'}->{$class}->{$bench}->{$onetune}) eq 'ARRAY') &&
                                @{$rf->{'flaglist'}->{$class}->{$bench}->{$onetune}}
                               );
                            if (!$printed_title) {
                                push @output, '', [ $class2title{$class}, 'center' => 1 ],
                                                  [ '-' x length($class2title{$class}), 'center' => 1 ];
                                $printed_title = 1;
                            }
                            if (!$printed_lang) {
                                push @output, $rf->{'var2desc'}->{$lang}.':', '';
                                $printed_lang = 1;
                            }
                            my @strings = ();
                            my $flags = $rf->{'flaglist'}->{$class}->{$bench}->{$onetune};
                            my $strings = $classref->{$bench}->{$onetune};
                            for(my $i = 0; $i < @{$flags}; $i++) {
                                next unless (istrue($flags->[$i]->[2]->{'display'}) || $r->{'review'});
                                push @strings, $strings->[$i];
                            }
                            push @output, dump_lines(" $bench: ", $rf->{'maxbench'} + 3, \@strings), '';
                            if (::check_elem(undef, $rf, 'mismatch', $class, $bench, $onetune)) {
                                $mismatch += $rf->{'mismatch'}->{$class}->{$bench}->{$onetune};
                            }
                            $donebench{$bench}++;
                        }
                    }
                }
            }

            # Next dump class flags by tuning level, with the common per-language
            # set at the top, followed by benchmark-specific settings
            my $printed_tune = 0;
            my $classref = undef;
            if (::check_elem('HASH', $rf, 'bylang', 'stringlist', $class, $tune)) {
                $classref = $rf->{'bylang'}->{'stringlist'}->{$class}->{$tune};
            }
            foreach my $lang (sort ::bylang keys %langstodo) {
                last if $class eq 'portability'; # Portability is by benchmark
                my $printed_lang = 0;

                # First check for by-language list
                if (defined($classref) &&
                    ::check_elem('ARRAY', $classref, $lang) &&
                    @{$classref->{$lang}}) {
                    if (!$printed_tune) {
                        my $title = ucfirst($tune).' '.$class2title{$class};
                        push @output, '', [ $title, 'center' => 1 ],
                                          [ '-' x length($title), 'center' => 1 ];
                        $printed_tune = 1;
                    }
                    my @strings = ();
                    my $flags = $rf->{'bylang'}->{'flaglist'}->{$class}->{$tune}->{$lang};
                    for(my $i = 0; $i < @{$flags}; $i++) {
                        next if (!istrue($flags->[$i]->[2]->{'display'}) && !istrue($r->{'review'}));
                        push @strings, $classref->{$lang}->[$i];
                    }
                    my $langtitle = $rf->{'var2desc'}->{$lang};
                    if ($rf->{'langmatch'}->{$class}->{$tune}->{$lang} == 2) {
                        $langtitle .= ' (except as noted below)';
                    }
                    push @output, dump_lines($langtitle.': ', 5, \@strings, { 'title_alone' => 1 }), '';
                    $printed_lang = 1;
                    if (::check_elem(undef, $rf, 'bylang', 'mismatch', $class, $tune, $lang)) {
                        $mismatch += $rf->{'bylang'}->{'mismatch'}->{$class}->{$tune}->{$lang};
                    }
                }

                # Now do the benchmark-specific list (if any)
                if (::check_elem('HASH', $rf, 'stringlist', $class)) {
                    my $classref = $rf->{'stringlist'}->{$class};
                    foreach my $bench (sort keys %{$classref}) {
                        next if $donebench{$bench};
                        next if $rf->{'langs'}->{$bench}->{$tune} ne $lang;
                        next unless ::check_elem('ARRAY', $classref, $bench, $tune);
                        next unless @{$classref->{$bench}->{$tune}};
                        if (!$printed_tune) {
                            my $title = ucfirst($tune).' '.$class2title{$class};
                            push @output, '', [ $title, 'center' => 1 ],
                                              [ '-' x length($title), 'center' => 1 ];
                            $printed_tune = 1;
                        }
                        if (!$printed_lang) {
                            push @output, $rf->{'var2desc'}->{$lang}.':', '';
                            $printed_lang = 1;
                        }
                        my @strings = ();
                        my $flags = $rf->{'flaglist'}->{$class}->{$bench}->{$tune};
                        my $strings = $classref->{$bench}->{$tune};
                        for(my $i = 0; $i < @{$flags}; $i++) {
                            next unless (istrue($flags->[$i]->[2]->{'display'}) || $r->{'review'});
                            push @strings, $strings->[$i];
                        }
                        push @output, dump_lines(" $bench: ", $rf->{'maxbench'} + 3, \@strings), '';
                        if (::check_elem(undef, $rf, 'mismatch', $class, $bench, $tune)) {
                            $mismatch += $rf->{'mismatch'}->{$class}->{$bench}->{$tune};
                        }
                    }
                }
            }

            if ($class eq 'portability') {
                # Do the portability flags on a per-benchmark basis; this is mostly
                # a copy of the code above.
                my @port_tunes = ($tune);
                my @titles = ( ucfirst($tune).' '.$class2title{$class} );
                if ($section_order == 1) {
                    # 0ld sk00l order means we have to do all tuning outputs
                    # here
                    if (!exists($rf->{'allmatch'}->{$class}) ||
                        $rf->{'allmatch'}->{$class} != 1) {
                        # ... but only if they shouldn't be merged.
                        @port_tunes = @tunes;
                        @titles = map { ucfirst($_).' '.$class2title{$class} } @port_tunes;
                    } else {
                        # Old order, but the section is merged (as it should
                        # always be, in the old order)
                        @titles = ( $class2title{$class} );
                    }
                }
                foreach my $port_tune (@port_tunes) {
                    my $title = shift(@titles);
                    $printed_tune = 0;
                    my $did_output = 0;
                    if (::check_elem('HASH', $rf, 'stringlist', $class)) {
                        my $classref = $rf->{'stringlist'}->{$class};
                        foreach my $bench (sort keys %{$classref}) {
                            next if $donebench{$bench};
                            next unless ::check_elem('ARRAY', $classref, $bench, $port_tune);
                            next unless @{$classref->{$bench}->{$port_tune}};
                            if (!$printed_tune) {
                                push @output, '', [ $title, 'center' => 1 ],
                                                  [ '-' x length($title), 'center' => 1 ];
                                $printed_tune = 1;
                            }
                            my @strings = ();
                            my $flags = $rf->{'flaglist'}->{$class}->{$bench}->{$port_tune};
                            my $strings = $classref->{$bench}->{$port_tune};
                            for(my $i = 0; $i < @{$flags}; $i++) {
                                next unless (istrue($flags->[$i]->[2]->{'display'}) || $r->{'review'});
                                push @strings, $strings->[$i];
                            }
                            push @output, dump_lines(" $bench: ", $rf->{'maxbench'} + 3, \@strings);
                            $did_output++ if @strings;
                            if (::check_elem(undef, $rf, 'mismatch', $class, $bench, $port_tune)) {
                                $mismatch += $rf->{'mismatch'}->{$class}->{$bench}->{$port_tune};
                            }
                        }
                    }
                    if ($mismatch) {
                        push @output, '(*) Indicates portability flags found in non-portability variables';
                        $mismatch = 0;
                    }
                    push @output, '' if $did_output;
                }
            } else {
                # Portability is taken care of above...

                if ($mismatch) {
                    if ($class eq 'optimization') {
                        push @output, '(*) Indicates optimization flags found in portability variables';
                    } elsif ($class eq 'portability') {
                        push @output, '(*) Indicates portability flags found in non-portability variables';
                    } elsif ($class eq 'compiler') {
                        push @output, '(*) Indicates compiler flags found in non-compiler variables';
                    }
                }
                $mismatch = 0;
            }
        }
    }

    if (defined($::website_formatter) && $::website_formatter &&
        defined($r->{'flagsurl'}) && $r->{'flagsurl'} ne '') {
      my $urls = $r->{'flagsurl'};
      if ((reftype($urls) ne 'ARRAY')) {
          # Shouldn't happen, but just in case
          $urls = [ $urls ];
      }
      my $plural = undef;
      my (@html_output, @xml_output);
      foreach my $url (@{$urls}) {
          my $html_url = $url;
          $html_url =~ s/\.xml$/\.html/;
          push @html_output, $html_url;
          push @xml_output, $url;
          $plural = 's' if defined($plural);
          $plural = '' unless defined($plural);
      }

      if (@{$urls} > 1) {
        push @output, '', 'The flags files that were used to format this result can be browsed at', @html_output;
      } else {
        push @output, '', 'The flags file that was used to format this result can be browsed at', @html_output;
      }
      push @output, '', "You can also download the XML flags source${plural} by saving the following link${plural}:", @xml_output;
    }

    push @output, '';

    push @output, footer();

    push @output, @errors;
    unshift @output, @errors;
    push @output, [ '-', 'divider' => 1 ];
    push @output, 'For questions about this result, please contact the tester.';
    push @output, 'For other inquiries, please contact webmaster@spec.org.';
    push @output, 'Copyright '.::copyright_dates().' Standard Performance Evaluation Corporation';
    push @output, "Tested with SPEC $::suite v".$r->{'suitever'}.'.';
    push @output, 'Report generated on '.&::ctime(time)." by $::suite ASCII formatter v$asc_version.";

    # Wave through and find the longest line (for center, etc)
    my $longline = 78;  # Assume 80 columns are always available
    foreach my $line (@output) {
      if (ref($line) eq 'ARRAY') {
        $longline = length($line->[0]) if length($line->[0]) > $longline;
      } else {
        $longline = length($line) if length($line) > $longline;
      }
    }

    # Now fix up lines that need it
    for(my $i = 0; $i < @output; $i++) {
      next unless ref($output[$i]) eq 'ARRAY';
      my ($txt, %attr) = @{$output[$i]};
      if ($attr{'divider'}) {
        $txt = substr($txt, 0, 1) x $longline;
        delete $attr{'divider'};
      }
      if ($attr{'center'}) {
        $txt = center($txt, $longline);
        delete $attr{'center'};
      }
      if (keys %attr) {
        ::Log(150, "WARNING: Unknown attributes found on line $i of txt output: ".join(', ', sort keys %attr)."\n");
      }
      $output[$i] = $txt;
    }

    return (\@output, []);
}

sub format_table {
    my ($resultobj, $fields, $table, $logs, $is_nc) = @_;
    my @rc;
    for my $benchname (sort keys %$table) {
	my $tr = $table->{$benchname};
	my $array = { 'base' => [], 'peak' => [] };
	$array->{'base'} = [@{$tr->{'base'}}] if (reftype($tr->{'base'}) eq 'ARRAY');
	$array->{'peak'} = [@{$tr->{'peak'}}] if (reftype($tr->{'peak'}) eq 'ARRAY');
	my ($base, $peak);

	while (@{$array->{'base'}} || @{$array->{'peak'}}) {
	    my $line = '';
            my %fields_seen = ();
	    for my $tune (qw(base peak)) {
		my $ref = $array->{$tune};
                my $resline = shift @{$ref};
                foreach my $field (@{$fields}) {
                    my $name = $field->{'val'};
                    next if ($field->{'notune'} && $fields_seen{$name});
                    $fields_seen{$name}++;
                    my $pad = defined($field->{'pad'}) ? $field->{'pad'} : 1;
                    my $width = $field->{'width'};
                    my $val = '';
                    if (defined($resline) && reftype($resline) eq 'HASH') {
                        $val = $resline->{$name};
                        if ($field->{'num_convert'} && $val+0 > 0) {
                            $val = sprintf($field->{'num_convert'}, $val);
                        }
                        if ($field->{'sig_fig'} > 0 && $val+0 > 0) {
                            $val = significant($width, $field->{'sig_fig'}-1, $logs->{$tune}->{$name}, $val, $field->{'sig_hack'}, $is_nc);
                        }
                    }
                    $line .= sprintf "%*s%*s", $width, $val, $pad, ' ';
		}
	    }
	    push @rc, $line;
	}
    }
    return @rc;
}

sub screen_format {
    # This does the screen format, which is really just the summary table
    my ($me, $r, $fn, $isasc, $invalid, $nc) = @_;
    my $is_nc = 0;

    if (@{$nc}) {
        if (istrue($r->{'nc_is_cd'})) {
            $is_nc = 3; # CD
        } elsif (istrue($r->{'nc_is_na'})) {
            $is_nc = 2; # NA
        } else {
            $is_nc = 1; # NC
        }
    }
    my @fields = ();
    my @output = ();
    my $what_ = ' Ref. ';
    my $rmode = ' Ratio';
    if (istrue($r->rate)) {
       $what_ = 'Copies';
       $rmode = ' Rate ';
    } elsif ($::lcsuite eq 'cpuv6') {
       $what_ = ' Thrds';
       $rmode = ' Ratio';
    } elsif ($::lcsuite eq 'mpi2007') {
       $what_ = ' Ranks';
       $rmode = ' Ratio';
    } elsif ($::lcsuite eq 'omp2012') {
       $what_ = ' Thrds';
       $rmode = ' Ratio';
    }

    # The field widths that these need to match are in format_table()
    if (istrue($r->power)) {
        if ($::lcsuite ne 'omp2012') {
            push @output,
            '                           Estimated                         Estimated' if $invalid;
            push @output,
            '                Base   Base    Base    Base       Peak   Peak    Peak    Peak',
            "Benchmarks     $what_ Energy  RunTime $rmode     $what_ Energy  RunTime $rmode",
            '-------------- ------ ------- ------- -------    ------ ------- ------- -------   ';
            @fields = ({ 'val' => 'name',      'width' => -14,                'notune' => 1 },
                       { 'val' => lc($what_),  'width' => 6,                  'num_convert' => '%d' },
                       { 'val' => 'energykJ',  'width' => 7,  'sig_fig' => 3 },
                       { 'val' => 'time',      'width' => 7,  'sig_fig' => 3, 'sig_hack' => 1 },
                       { 'val' => 'ratio',     'width' => 7,  'sig_fig' => 3 },
                       { 'val' => 'selected',  'width' => 2                  },
                      );
        } else {
            push @output,
            '                                 Estimated                                            Estimated' if $invalid;
            push @output,
            '                Base   Base    Base   Base   Base   Base   Base      Peak   Peak    Peak   Peak   Peak   Peak   Peak',
            "Benchmarks     $what_ RunTime $rmode Energy MaxPwr AvgPwr ERatio    $what_ RunTime $rmode Energy MaxPwr AvgPwr ERatio",
            '-------------- ------ ------- ------ ------ ------ ------ ------    ------ ------- ------ ------ ------ ------ ------   ';
            @fields = ({ 'val' => 'name',         'width' => -14,                'notune' => 1 },
                       { 'val' => lc($what_),     'width' => 6,                  'num_convert' => '%d' },
                       { 'val' => 'time',         'width' => 7,  'sig_fig' => 3, 'sig_hack' => 1 },
                       { 'val' => 'ratio',        'width' => 6,  'sig_fig' => 3 },
                       { 'val' => 'energykJ',     'width' => 6,  'sig_fig' => 3 },
                       { 'val' => 'max_power',    'width' => 6,  'sig_fig' => 3 },
                       { 'val' => 'avg_power',    'width' => 6,  'sig_fig' => 3 },
                       { 'val' => 'energy_ratio', 'width' => 6,  'sig_fig' => 3 },
                       { 'val' => 'selected',     'width' => 2                  },
                      );
        }

    } else {
        push @output,
        '                       Estimated                       Estimated' if $invalid;
        push @output,
        '                Base     Base       Base        Peak     Peak       Peak',
        "Benchmarks     $what_  Run Time    $rmode      $what_  Run Time    $rmode",
        '-------------- ------  ---------  ---------    ------  ---------  ---------   ';
        @fields = ({ 'val' => 'name',     'width' => -14,                'notune' => 1                     },
                   { 'val' => lc($what_), 'width' => 6,                  'num_convert' => '%d', 'pad' => 2 },
                   { 'val' => 'time',     'width' => 9,  'sig_fig' => 3, 'sig_hack' => 1,       'pad' => 2 },
                   { 'val' => 'ratio',    'width' => 9,  'sig_fig' => 3                                    },
                   { 'val' => 'selected', 'width' => 2                                                     },
                  );
    }

    my $table    = {};
    my $results  = {};
    my %smallest = ( );
    my %benchseen = ();
    # base is always 'seen' in order to get the benchmark name in the table
    my %tuneseen = ( 'base' => 1 );

    # Go through the benchmarks that have results.  We'll catch the missed
    # ones afterward.
    for my $bench (sort keys %{$r->{'results'}}) {
	for my $tune (sort keys %{$r->{'results'}{$bench}}) {
	    for my $res ($r->benchmark_results_list($bench, $tune)) {
		# If we don't get here, we haven't "seen" them...
		$benchseen{$bench.$tune} = 1 unless exists $benchseen{$bench.$tune};
		$tuneseen{$tune} = 1 unless exists $benchseen{$tune};
                # Stuff the result with info from all supported benchmarks;
                # what's output is controlled by @fields
                my $tmp = {
                            'name' => $bench, 'tune' => $tune,
                            ::result_to_hash($res, $r->size_class, $is_nc)
                          };
		print "\%tmp = (",join(', ', map { "$_ => ".$tmp->{$_} } keys %{$tmp}),")\n" if ($debug & 2);

                # Check to see if any of the current values are smaller than
                # the saved ones.  This is used for figuring out where to put
                # decimal points later.
                foreach my $field (keys %{$tmp}) {
                    if ($tmp->{$field} != 0     # Ignore non-number strings
                        &&
                        (!defined($smallest{$field}->{$tune})
                         ||
                        ($smallest{$field}->{$tune} > $tmp->{$field}))
                       ) {
                        $smallest{$field}->{$tune}  = $tmp->{$field};
                        print "smallest{$field}->{$tune} = ".$smallest{$field}->{$tune}."\n" if ($debug & 2);
                    }
                }

                # Selected results go in the lower table
		if ($res->selected && $r->size_class eq 'ref') {
		    push @{$results->{$bench}{$tune}}, $tmp;
		    $benchseen{$bench.$tune} = 'selected';
		}
                # All results go in the top table
		push @{$table->{$bench}{$tune}}, $tmp;
	    }
	}
    }
    for my $bench (sort keys %{$r->benchmarks}) {
	for my $tune (sort keys %tuneseen) {
            next if (exists($benchseen{$bench.$tune}) &&
                     ($benchseen{$bench.$tune} eq 'selected'));
	    my $tmp = { 'name' => $bench, 'tune' => $tune, 'selected' => 'NR', 'valid' => 'NR' };
	    push @{$table->{$bench}{$tune}}, $tmp unless $benchseen{$bench.$tune};
	    push @{$results->{$bench}{$tune}}, $tmp;
	}
    }

    # Figure out the number of decimal places for each field
    my %logs = ();
    my %fields = ();
    foreach my $field (keys %smallest) {
        foreach my $tune (keys %{$smallest{$field}}) {
            if (defined($smallest{$field}->{$tune})
                &&
                $smallest{$field}->{$tune} > 0
               ) {
                $logs{$tune}->{$field} = log($smallest{$field}->{$tune}) / log(10);
                $fields{$field}++;
            }
        }
    }
    if ($debug) {
        foreach my $field (sort keys %fields) {
            print "\$logs{$field} = (";
            foreach my $tune (sort keys %smallest) {
                print "'$tune' => ".(defined($logs{$tune}->{$field}) ? $logs{$tune}->{$field} : 'undef').", ";
            }
            print "\n";
        }
    }

    if ($isasc && istrue($r->table)) {
	push @output, format_table($r, \@fields, $table, \%logs, $is_nc);
	push @output, '=' x column_end(\@fields, 2);
    }
    push @output, format_table($r, \@fields, $results, \%logs, $is_nc);

    my $est;
    $est = 'Est. ' if ($invalid);

    foreach my $mref (
                      [ $r->baseenergymean, 'energy_ratio', $r->baseenergyunits, 'base' ],
                      [ $r->basemean,       'ratio',        $r->baseunits,       'base' ],
                      [ $r->peakenergymean, 'energy_ratio', $r->peakenergyunits, 'peak' ],
                      [ $r->peakmean,       'ratio',        $r->peakunits,       'peak' ],
                     ) {
        my ($mean, $field, $units, $tune) = @{$mref};
        if ($mean =~ /\d/) {
          $mean = significant(8, undef, $logs{$tune}->{$field}, $mean, 0, $is_nc);
        }
        my $col = column_end(\@fields, ($tune eq 'base') ? 1 : 2, $field);
        if (defined($col)) {
            push @output, sprintf (" %*s%8s", 
                                   ($col - 8 - 1) * -1,
                                   $est . fixup_trademarks($units), $mean);
        }
    }

    return @output;
}

sub format_info {
    my ($title, $ref) = @_;
    return () if !@$ref;

    my @output;
    push @output, '', '', [ $title, 'center' => 1 ],
                          [ '-' x length($title), 'center' => 1 ];
    for my $item (@{$ref}) {
	my ($name, @vals) = @$item;
	if (!@vals) {
	    push (@output, sprintf ('%20.20s: --', $name));
	} else {
	    my $val = shift @vals;
	    push (@output, sprintf ('%20.20s: %s', $name, $val));

	    while (@vals) {
		$val = shift @vals;
		if (ref($val) eq '') {
		    push (@output, sprintf ('%20.20s  %s', '', $val));
		} elsif ((::reftype($val) eq 'ARRAY')) {
		    unshift @vals, @{$val};
		}
	    }
	}
    }
    return @output;
}

sub dump_lines {
    my ($title, $len, $strings, $opts) = @_;
    my @output = ();
    my $line = '';
    my $printed = 0;
    $opts = {} unless (reftype($opts) eq 'HASH');
    return () unless (reftype($strings) eq 'ARRAY') && @$strings;

    if ($opts->{'title_alone'}) {
      $printed = 1;
      push @output, $title;
    }

    foreach my $string (@{$strings}) {
	if ($line eq '') {
	    $line = $string;
	} elsif (length($line.', '.$string) + $len > 78) {
	    push @output, sprintf "%*s%s", $len, ($printed) ? '' : $title, $line;
	    $printed++;
	    $line = $string;
	} else {
            if (0) {
              # No commas; too "confusing"
              $line .= ", $string";
            } else {
              $line .= " $string";
            }
	}
    }
    if ($line ne '') {
	push @output, sprintf "%*s%s", $len, ($printed) ? '' : $title, $line;
    }

    return @output;
}

sub dump_power {
    my ($r, @power_info) = @_;
    my %thinglabel = ( 'power' => 'POWER ANALYZER',
                       'temperature' => 'TEMPERATURE METER'
                     );
    my @rc = ();

    if (istrue($r->power)) {
        push @rc, format_info('POWER',    [ @power_info ]);
        foreach my $powerthing (qw(power temperature)) {
            for(my $i = 0; $i < @{$r->{'meterlist'}->{$powerthing}}; $i++) {
                my $instance = (@{$r->{'meterlist'}->{$powerthing}} > 1) ? ' #'.($i + 1) : '';
                push @rc, format_info($thinglabel{$powerthing}.$instance, [ $r->info_format($r->{'meters'}->{$powerthing}->{$r->{'meterlist'}->{$powerthing}->[$i]}) ]);
            }
        }
    }

    return @rc;
}
sub footer {
  return ::trademark_lines('  ', %trademarks_done);
}

sub munge_links {
    my (@lines) = @_;
    my @newlines = ();

    foreach my $line (@lines) {
        # LINKs are treated the same no matter where they're formatted
        $line =~ s/LINK\s+(\S+)\s+AS\s+(?:\[([^]]+)\]|(\S+))/$2$3 ($1)/go;

        my $count = 0;
        my $temp = $line;
        while ($count < 40 && $line =~ /(ATTACH\s+(\S+)\s+AS\s+(?:\[([^]]+)\]|(\S+)))/g) {
            my ($section, $url, $text) = ($1, $2, $3.$4);
            $text =~ s/^\[(.*?)\]$/$1/;
            $temp =~ s/\Q$section\E/$text ($url)/;
            $count++;
        }
        push @newlines, $temp;
    }
    return @newlines;
}

# Look in the input string for trademarks and mark them up as appropriate.
# Also keep track of which ones were used so that they can be mentioned in
# the result page footer.
sub fixup_trademarks {
  my ($str) = @_;

  foreach my $tm (sort { length($b) <=> length($a) } keys %::trademarks) {
    next if exists($trademarks_done{$tm});
    my $tmre = qr/\b${tm}((?=[^a-zA-Z])|\b)/;
    my $tmcode = $::trademarks{$tm};
    if ((reftype($::trademarks{$tm}) eq 'ARRAY')) {
        if ($::trademarks{$tm}->[1]) {
            $tmre = qr/\b${tm}/;
            $tmcode = $::trademarks{$tm}->[0];
        }
    }
    if ($str =~ /$tmre/) {
        $trademarks_done{$tm}++;
        $str =~ s/$tmre/${tm}$code2mark{$tmcode}/;
    }
  }

  return $str;
}

# column_end -- given the list of fields, return the column position of
# the end of the specified field, or if not specified, the full width of
# the table (either the full table or just the tuning-specific parts) in
# characters
sub column_end {
  my ($fields, $instance, $column) = @_;
  print "column_end($fields, instance=$instance, column='$column')\n" if ($debug & 8);

  $instance = 1 unless defined($instance) && $instance > 1;
  $column = '' unless defined($column);
  $fields = [] unless reftype($fields) eq 'ARRAY';
  my $width = 0;
  my %seen = ();
  my $lastpad = 0;
  for(; $instance > 0; $instance--) {
    foreach my $field (@{$fields}) {
      next if $field->{'notune'} && $seen{$field->{'val'}};
      $seen{$field->{'val'}}++;
      $lastpad = ($field->{'pad'} ? $field->{'pad'} : 1);
      my $tmpwidth = abs($field->{'width'}) + $lastpad;
      $width += $tmpwidth;
      print "$instance:$width [$field->{'val'} => $tmpwidth (orig $field->{'width'})]\n" if ($debug & 8);
      last if $field->{'val'} eq $column && $instance == 1;
    }
  }
  $width -= $lastpad;

  if ($column ne '' && !exists($seen{$column})) {
      print "undef RETURN\n" if ($debug & 8);
      return undef;
  } else {
      print "$width RETURN\n" if ($debug & 8);
      return $width;
  }
}

# significant -- format a floating point value into N significant digits
#                (resulting in 3 or fewer decimal places)
# width of text string to return
# log of minimum output (how many decimal places do we want)
# log of smallest overall value (how many decimals will we be using for sure)
# value to format
sub significant {
    my ($width, $min_log, $low_log, $value, $hack, $is_nc) = @_;
    print "significant(width=$width, min_log=$min_log, low_log=$low_log, val=$value, hack=$hack, is_nc=$is_nc) called from ".join('|',caller).".\n" if ($debug & 4);

    return 'CD' if ($is_nc == 3);
    return 'NA' if ($is_nc == 2);
    return 'NC' if ($is_nc);

    my $retval = ::significant_base($value, $min_log, undef, $hack, ($debug & 4));
    my $my_dp = ::significant_base($value, $min_log, 2, $hack, 0);

    my $space = 0;
    my $dp        = ($low_log >= $min_log)? 0 : int(3 - $low_log);
    print "  my_dp=$my_dp dp=$dp\n" if ($debug & 4);
    $space = ' ' x ($dp - $my_dp);
    $space .= ' ' if ($dp && !$my_dp);   # Space for the decimal point
    print "  space='$space'\n" if ($debug & 4);
    $retval = sprintf('%*s%s', int($width-length($space)), $retval, $space);
    print "sprintf('%*s%s', int(\$width-length(\$space)), \$retval, \$space) =\n" if ($debug & 4);
    print "  sprintf('%*s%s', ".int($width-length($space)).", $retval, '$space') =\n" if ($debug & 4);
    print "    '$retval'\n" if ($debug & 4);

    return $retval;
}

sub center  { main::center(@_); }
sub jp { main::jp(@_); }
sub istrue { main::istrue(@_); }

# Unitish tests here
if (grep { $_ eq 'test:significant' } @ARGV) {
  my @tests = (
  # Start		Width	low_log	min_log			Hack?	Expected	Label
  [ 4629.42485,		9,	3,	3.55127978571904,	1,	'     4629',	'Round down w/hack' ],
  [ 1.017405,		9,	3,	-0.389410096112134,	0,	'    1.02 ',	'Round up LSD w/o hack' ],
  [ 0.999298,		9,	3,	-0.389410096112134,	0,	'    0.999',	'Truncate, no hack' ],
  [ 0.999981,		9,	3,	-0.389410096112134,	0,	'    1.00 ',	'Round up to next order of magnitude w/o hack' ],
  [ 4525.838739,	9,	3,	3.55127978571904,	1,	'     4526',	'Round up w/hack' ],
  [ 1.000919,		9,	3,	-0.389410096112134,	0,	'    1.00 ',	'Truncate, no hack' ],
  [ 0,			8,	3,	-0.4,			0,	'   0.00 ',	'Zero (special case)' ],
  [ 99.9298,		9,	3,	-0.389410096112134,	0,	'   99.9  ',	'Round down, no hack!' ],
  [ 99.9981,		9,	3,	-0.389410096112134,	0,	'  100    ',	'Round up to next order of magnitude w/o hack' ],
  );
  require Test::More; Test::More->import(tests => @tests*2);
  foreach my $testref (@tests) {
    my ($start, $width, $low_log, $min_log, $hack, $expected, $label) = @{$testref};
    my $val = significant($width, $low_log-1, $min_log, $start, $hack, 0);
    is(length($val), $width, 'Width of field for '.$label);
    if (!is($val, $expected, $label)) {
      $debug = 4;
      diag(significant($width, $low_log-1, $min_log, $start, $hack, 0));
      $debug = 0;
    }
  }
}
1;
