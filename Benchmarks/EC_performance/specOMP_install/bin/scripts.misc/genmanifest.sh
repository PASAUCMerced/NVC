#!/bin/sh
#
# genmanifest.sh - generate the top-level MANIFEST file
# No support is provided for this script.
#
# Copyright 1999-2012 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: genmanifest.sh 1727 2012-07-24 19:42:08Z CloyceS $

if [ -z "$SPEC" ]; then
    echo "SPEC variable is not set!";
    exit 1;
fi

# Tweak this; it's a regexp that recognizes the name of the suite tarball
# that lives in install_archives
suitetarballre='/(mpi200[0-9]|cpu20[0-9][0-9]|cpuv[0-9])(-.*)?\.(t[abx]z|tar.[gbx]z2?)(\.md5)?$'

# bzip2 is needed to generate sums for compressed content.  This won't happen
# in practice, but the capability should still be there.
if [ -n "$SPECBZIP" ]; then
    BZIPTRY=$SPECBZIP
else
    BZIPTRY="specbzip2 bzip2"
fi
BZIP=
for try in $BZIPTRY; do
    TMP=`$try --help >/dev/null 2>&1`
    if [ -z "$BZIP" -a $? -eq 0 ]; then
        BZIP=$try
    fi   
done
if [ -z "$BZIP" ]; then
    echo "No bzip2 found (tried $BZIPTRY).  Please add it to your PATH"
    echo "or set SPECBZIP to its location."
    exit 1
fi

# Don't tweak this
novc='( ( -name CVS -o -name .svn ) -prune ) -o'

cd $SPEC
rm -f MANIFEST SUMS.data

if [ -f tools/tools_src.tar.bz2 ]; then
  exclude_toolsrc="grep -v ^tools/src/"
else
  exclude_toolsrc=cat
fi

echo Generating MD5 sums for compressed data files
compressedre=''
for i in `find . $novc \( -type f -name '*.bz2' -print \) | grep /data/ | sed 's/^\.\///' | sort`; do
    # If this is a full working tree, there should already be an uncompressed
    # copy in the directory.  But do the decompression, because it's the file
    # that's shipping that's important...
    fname=`dirname $i`/`basename $i .bz2`
    compressedre="$compressedre|$fname"
    $BZIP -dc $i | specmd5sum --binary -e | sed "s|-|$fname|" >> SUMS.data
done
if [ "x$compressedre" = "x" ]; then
  compressedre=cat
else
  compressedre="egrep -v ^($compressedre)\$"
fi

echo Generating MD5 sums for distribution files
find . $novc \( -type f ! -name MANIFEST ! -name MANIFEST.tmp -print \) | \
  sed 's#^\./##' | \
  egrep -v '(\.ignoreme|\.cvsignore|\.DS_Store)' | \
  egrep -v $suitetarballre | \
  $compressedre | \
  egrep -v '^shrc\.bat$' | \
  egrep -v '^bin/specperldoc' | \
  egrep -v '^benchspec/common' | \
  egrep -v '^benchspec/.*/(exe|run)/' | \
  egrep -v '^result' | \
  egrep -v '^original\.src/(release_control|benchball)' | \
  egrep -v '^tools/src/buildtools.log/.*buildlog.txt$' | \
  $exclude_toolsrc | \
  sort | \
  xargs specmd5sum --binary -e >> MANIFEST
