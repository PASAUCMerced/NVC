#
# config.pl
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: config.pl 1835 2012-08-27 20:00:18Z CloyceS $
#
package Spec::Config;

use strict;
use IO::File;
use Safe;
use File::Basename;
use Scalar::Util qw(reftype);

require 'config_common.pl';

my $version = '$LastChangedRevision: 1835 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'config.pl'} = $version;

sub copies {
  my $me = shift;
  return 1 unless istrue($me->rate);
  my @check = qw(clcopies);
  push @check, 'copies' unless $me->tune eq 'base';
  foreach my $check (@check) {
    my $tmp = $me->accessor_nowarn($check);
    next unless defined($tmp) && $tmp ne '';
    return main::expand_ranges(split(/,+|\s+/, $tmp));
  }
  return main::expand_ranges(@{$me->copylist});
}

sub ranks {
  my $me = shift;

  my $what = ($::lcsuite eq 'mpi2007') ? 'ranks' : 'threads';

  my @check = ($what, 'clranks');
  foreach my $check (@check) {
    my $tmp = $me->accessor_nowarn($check);
    next unless defined($tmp) && $tmp ne '';
    return $tmp;
  }
  return $::global_config->{$what} > 0 ? $::global_config->{$what} : 1;
}

1;
