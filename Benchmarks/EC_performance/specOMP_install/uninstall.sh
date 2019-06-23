#!/bin/sh

#
#  uninstall.sh - uninstalls CPU tools binaries
#  Copyright 2005-2010 by Standard Performance Evaluation Corporation
#
#  Author: Cloyce D. Spradling
#

SUITE=omp2001

is_spec_dir() {
    [ -f "$1/bin/packagename" -a    \
      -d "$1/tools/bin"       -a \( \
      -x "$1/bin/runspec\;1"  -o    \
      -x "$1/bin/runspec.\;1" -o    \
      -x "$1/bin/runspec."    -o    \
      -x "$1/bin/runspec"     \) ]
}

clear=`tput clear`
echo "${clear}SPEC $SUITE Tools Uninstaller"
echo

# We want everything to be world readable
umask 022

# Set the locale, if it isn't already set and the user hasn't forbidden it
if [ -z "$SPEC_INSTALL_LOCALE_OK" ]; then
    if [ -z "$LC_ALL" -o -z "$LC_LANG" ]; then
        LC_ALL=C
        LC_LANG=C
        export LC_ALL LC_LANG
    fi
fi

# Find top of SPEC heirarchy
if [ -n "$SPEC" ] ; then
    if is_spec_dir "$SPEC"; then
	if [ "$SPEC" != "`pwd`" ]; then
	    echo "The SPEC environment variable is already set to \"$SPEC\","
            echo "which does not match the current directory (\"`pwd`\").  If you continue,"
            echo "de-installation will happen in \"$SPEC\"."
            echo "Is this the desired behavior?"
	    echo "Please enter 'yes' or 'no'."
	    read ans
	    ans=`echo $ans | tr YESNO yesno`
	    if [ "$ans" = 1 -o "$ans" = 'y' -o "$ans" = 'yes' ]; then
		true
	    else
                echo
                echo "Okay, \$SPEC is now unset.  Please pay special attention to the next"
                echo "non-blank line.  If it does not contain the location of an installation that"
                echo "you would like to uninstall, terminate the uninstall.sh process and try again."
                echo
		SPEC=
	    fi
	fi
    else
	SPEC=
    fi
fi
if [ -z "$SPEC" ]; then
    SPEC=`pwd`
    while [ -n "$SPEC" ]; do
	if is_spec_dir "$SPEC"; then
	    break;
	fi
	# At least some vendors' /bin/sh doesn't like this substitution
	#SPEC=${SPEC%/*}
	# Everyone should still have sed
        oldSPEC=$SPEC
	SPEC=`echo $SPEC | sed -e 's/\/[^\/]*$//'`
        if [ "$oldSPEC" = "$SPEC" ]; then
          # Nothing changed; time to bail
          break;
        fi
    done
fi
if [ -z "$SPEC" ]; then
    SPEC=`dirname "$0"`
    while [ -n "$SPEC" ]; do
	if is_spec_dir "$SPEC"; then
	    break;
	fi
	# At least some vendors' /bin/sh doesn't like this substitution
	#SPEC=${SPEC%/*}
	# Everyone should still have sed
        oldSPEC=$SPEC
	SPEC=`echo $SPEC | sed -e 's/\/[^\/]*$//'`
        if [ "$oldSPEC" = "$SPEC" ]; then
          # Nothing changed; time to bail
          break;
        fi
    done
fi
if [ -n "$SPEC" ] && is_spec_dir "$SPEC"; then
    echo "Top of $SUITE tree is '$SPEC'"
else
    echo "Can't find the top of your benchmark tree!  Please change to your benchmark"
    echo "directory and run this program ($0) again!"
    exit 1
fi

echo "About to remove tools installation from \"$SPEC\"."
echo "Is this the desired behavior?"
echo "Please enter 'yes' or 'no'."
read ans
ans=`echo $ans | tr YESNO yesno`
if [ "$ans" = 1 -o "$ans" = 'y' -o "$ans" = 'yes' ]; then
    true
else
    echo
    echo "Uninstallation aborted."
    exit;
fi

if cd "$SPEC" ; then
    true
else
    echo "Huh?  Can't cd into spec directory '$SPEC'"
    exit 1
fi

if bin/relocate --undo; then
    true
else
    errors="${errors}Error un-relocating Perl tools.  The next installation will fix them
up.
"
fi

# Uninstall binaries here
rm -rf bin/lib

# UNinstall previously installed tools.  This might not get everything,
# but it'll get everything that might not be overwritten by the next
# installation.
if [ -f "$SPEC/SUMS.tools" ]; then
    echo "Removing previous tools installation"
    (cd "$SPEC"; cat SUMS.tools | grep bin/ | awk '{print $4}' | xargs rm -f)
    # At this point bin/lib should be empty, but just to be sure...
    rm -rf "$SPEC/bin/lib"
    rm -f "$SPEC/bin/packagename"
    rm -f "$SPEC/SUMS.tools"
fi


if [ -n "$errors" ]; then
    echo $errors
    exit 1
fi

exit 0
