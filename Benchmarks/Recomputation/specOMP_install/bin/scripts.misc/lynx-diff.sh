#!/bin/bash
#
# lynx-diff.sh - use lynx to produce side-by-side text diff of web pages 
# No support is provided for this script.
#
# Copyright 2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#  $Id: lynx-diff.sh 1164 2011-08-19 19:20:01Z CloyceS $
#
# J.Henning 8/2011
#


#==============================================================================
function shortusage {
   echo "Usage: $0 [-h] [-k] [-o outfile] [-s] [-t tmpdir] [-w width] file1 file2"
}
function usage {
   shortusage
   cat <<EOF

      -h             Print this message and exit
      -k             Keep temporaries
      -o outfile     Destination for side-by-side diff file 
                     Default: tmpdir/lynx-diff.txt
      -s             Silent mode
      -t tmpdir      Temporary directory, default is your
                     current TMPDIR, or else /tmp/$USER
      -w width       Width of the lynx output pages. Default: 80
                     (The diff will be a bit over 2x as wide.)

   This program uses lynx ($LYNX) to create text versions of
   file1 and file2 using your specified pagewidth.  The files
   are written to:
      tmpdir/${lynxout}1.txt
      tmpdir/${lynxout}2.txt
   The above are *removed* at the end, unless you say "-k"

   The above are then run through gnu diff ($DIFF) to create 
   a side-by-side diff 

EOF
}
#==============================================================================


# gnudiff needed
DIFF=/usr/bin/diff
MD5SUM=/usr/bin/md5sum
LYNX=/usr/bin/lynx
lynxout=lynx.out  # a portion of suffix for its output

if [[ "$TMPDIR " == " " ]]
then
   tmpdir=/tmp/$USER
else 
   tmpdir=$TMPDIR
fi

outfile=
keep=no
pagewidth=80
silent=no

while getopts "hko:st:w:" opt
do
   case $opt in
      h)
         usage
         exit
         ;;
      k)
         keep=yes
         ;;
      o)
         outfile=$OPTARG
         ;;
      s)
         silent=yes
         ;;
      t)
         tmpdir=$OPTARG
         ;;
      w)
         pagewidth=$OPTARG
         ;;
      \?)
         shortusage
         exit 1
         ;;
   esac
done
shiftby=`expr $OPTIND \- 1`
shift $shiftby

if [[ "$outfile " == " " ]]
then
   outfile="$tmpdir/lynx-diff.txt"
fi

diffwidth=$(($pagewidth*2+8))

# verify files exist
file1=$1
file2=$2
if (! [ -e $file1 ] )
then
   echo "$file1 not found"
   exit
fi
if (! [ -e $file2 ] )
then
   echo "$file2 not found"
   exit
fi

# prepend current dir if needed
if [[ "${file1:0:2}" == "./" ]]
then
   file1=`pwd`/${file1:2}
elif [[ "${file1:0:1}" != "/" ]]
then 
   file1=`pwd`/$file1
fi
if [[ "${file2:0:2}" == "./" ]]
then
   file2=`pwd`/${file2:2}
elif [[ "${file2:0:1}" != "/" ]]
then 
   file2=`pwd`/$file2
fi

#echo "file1: '$file1'"
#echo "file2: '$file2'"

mkdir -p $tmpdir

# grab the md5sums
mdsum1=`$MD5SUM $file1`
mdsum2=`$MD5SUM $file2`
mdsum1=${mdsum1:0:32}
mdsum2=${mdsum2:0:32}

f1dirname=`dirname $file1`
f2dirname=`dirname $file2`
f1basename=`basename $file1`
f2basename=`basename $file2`
f1dir_sub=${f1dirname:0:$pagewidth}
f2dir_sub=${f2dirname:0:$pagewidth}
f1base_sub=${f1basename:0:$pagewidth}
f2base_sub=${f2basename:0:$pagewidth}

date > $outfile
echo >> $outfile
halfdiffwidth=$(($diffwidth/2))
printf "%-${halfdiffwidth}s %s\n" $f1dir_sub $f2dir_sub >> $outfile
printf "%-${halfdiffwidth}s %s\n" $f1base_sub $f2base_sub >> $outfile
printf "%-${halfdiffwidth}s %s\n\n" $mdsum1 $mdsum2 >> $outfile

lynxout=lynx.out
lynxout1=$tmpdir/${lynxout}1.txt
lynxout2=$tmpdir/${lynxout}2.txt
$LYNX -dump -width $pagewidth -nolist file:///$file1 > $lynxout1
$LYNX -dump -width $pagewidth -nolist file:///$file2 > $lynxout2

$DIFF -w --side-by-side -W $diffwidth $lynxout1 $lynxout2 >> $outfile

if [[ "$keep" == "no" ]]
then
   rm $lynxout1 $lynxout2
else
   if [[ "$silent" != "yes" ]]
   then
      echo text versions are in: 
      echo "   $lynxout1"
      echo "   $lynxout2"
   fi
fi

if [[ "$silent" != "yes" ]]
then
   echo output written to: $outfile
fi
