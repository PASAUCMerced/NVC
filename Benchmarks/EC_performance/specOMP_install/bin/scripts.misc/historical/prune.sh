#!/bin/sh
#
# prune.sh - prune off a benchmark without breaking the tools (in some cases)
# No support is provided for this script
#
# Copyright 1999-2008 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: prune.sh 1061 2011-02-01 22:31:10Z keeper $
# 
# Using this will invalidate any runs of the affected suites

if [ -z "$1" ]; then
  echo 'Hey!  At least give me a benchmark name or two...'
  exit 1
fi

# Make sure variables and whatnot are set
if [ -z "$SPEC" ]; then
  if [ ! -f ./shrc ]; then
    echo Either source shrc beforehand or run me from the top level!
    exit 1
  else
    . ./shrc || exit 1
  fi
fi

TOFIX=""

cd $SPEC/benchspec
for i in $*; do
  for j in */$i*; do
  echo Nuking $j
    if [ -d $j ]; then
      rm -rf $j
      TOFIX="$TOFIX `dirname $j`"
    fi
  done
  for j in $TOFIX; do
    for k in $j/*bset; do
      cat $k | grep -v -- $i > $k.tmp
      cat $k.tmp > $k
      rm -f $k.tmp
    done
  done
done

