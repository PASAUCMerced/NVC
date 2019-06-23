#
# benchset.pm
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: benchset.pm 1198 2011-09-20 21:25:53Z CloyceS $
#

package Spec::Benchset;

use strict;
use Scalar::Util qw(reftype);
use vars '@ISA';

@ISA = (qw(Spec::Config));

my $version = '$LastChangedRevision: 1198 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'benchset.pm'} = $version;

require 'benchset_common.pl';

sub results_list {
    my ($me) = @_;
    my $benchhash = $me->{'results'};
    return () if ref($benchhash) ne 'HASH';
    my @result;
    for my $tune ('base', 'peak') {
	for my $bench (sort keys %$benchhash) {
	    next if ref($benchhash->{$bench}) ne 'HASH';
	    next if !exists $benchhash->{$bench}{$tune};
            if (!exists($benchhash->{$bench}{$tune}{'data'})) {
                Log(0, "WARNING: No data for $bench:$tune\n");
                next;
            }
	    push (@result, @{$benchhash->{$bench}{$tune}{'data'}});
	}
    }
    return @result;
}

sub benchmark_results_list {
    my ($me, $bench, $tune) = @_;
    my $benchhash = $me->{'results'};
    return () unless (reftype($benchhash) eq 'HASH');
    return () unless (reftype($benchhash->{$bench}) eq 'HASH');
    return () unless (reftype($benchhash->{$bench}{$tune}) eq 'HASH');

    if (!exists($benchhash->{$bench}{$tune}{'data'})) {
	Log(0, "WARNING: No data for $bench:$tune\n");
	return ();
    }
    return @{$benchhash->{$bench}{$tune}{'data'}};
}

1;
