#!csh -f

#
#  do_go.csh - the dirty guts of the CSH version of "go" and "ogo"
#  Copyright 2004-2011 Standard Performance Evaluation Corporation
#
#  Author: Cloyce D. Spradling
#
# $Id: do_go.csh 1164 2011-08-19 19:20:01Z CloyceS $
#

#
# There's really no reason for this to actually be _in_ CSH, except that it's
# guaranteed to be present (the user is using CSH, after all).  I also didn't
# realize it until I was done.  I just got caught up in the challenge, I guess.
#

# Enable this for _some_ debug output
set debug = 0

# Uncomment this for full trace output
#set verbose
 
# This is just so that we can test variables without fear of them being undef
if ( $?SPEC == 0 ) set SPEC=""
if ( $?GO == 0 ) set GO=""
if ( $?OGO_NO_WARN == 0 ) set OGO_NO_WARN=""

if ( "$SPEC" == "" ) then
    echo
    echo "The SPEC environment variable is not set\! Please source the cshrc and try again."
    echo
    exit
endif

set TOP  = $SPEC
set ppid = $argv[1]
shift
set type = $argv[1]
shift 
if ( $type == "go" ) then
    set SHRC_NO_GO=1
    goto do_go
else if ( $type == "ogo" ) then
    set SHRC_NO_GO=0
    if ( "$GO" == "" ) then
        echo
        echo "The GO environment variable is not set\! Please set it before using 'ogo'."
        echo
        exit
    endif
    if ( "$GO" != "" ) then
        if ( $#argv == 0 ) then
            if ( "$OGO_NO_WARN" == "" ) echo "Using value in GO for output_root: $GO"
            set TOP = `echo $GO | sed "s#^\([^/~]\)#$SPEC/\1#"`
            goto do_go
        endif
        switch( $argv[1] )
            case bin:
            case config:
            case doc:
            case Doc:
            case docs:
            case Docs:
            case int:
            case fp:
            case cpu:
            case mpi:
            case src:
            case data:
            breaksw
            default:
                switch( $argv[1] )
                    case data:
                    case src:
                    case Spec:
                    breaksw
                    default:
                        if ( "$OGO_NO_WARN" == "" ) echo "Using value in GO for output_root: $GO"
                        set TOP = `echo $GO | sed "s#^\([^/~]\)#$SPEC/\1#"`
                endsw
        endsw
    endif
    goto do_go
else
    echo Unknown action \"$type\" specified
    goto bad_end
endif

do_go:
    if ( $#argv == 0 ) then
        set BASE_DIR = $TOP
    else
        switch( $argv[1] )
            case -h:
            case --help:
                if ( $SHRC_NO_GO == 1) then
                    set ME = 'go'
                    set MYTOP = '$SPEC'
                else
                    set ME = 'ogo'
                    set MYTOP = '$GO'
                endif
                echo "Usage: $ME <destination>"
                echo "Destinations:"
                echo " top              : $MYTOP"
                echo ' docs             : $SPEC/Docs'
                echo ' config           : $SPEC/config'
                echo " result           : $MYTOP/result"
                echo " <benchmark> [...]: $MYTOP/benchspec/OMP2012/<benchmark>"
                echo "benchmark can be abbreviated: e.g. '$ME perlbench'"
                echo "See utility.html#$ME for more information."
                echo
                echo '$SPEC is currently set to "'$SPEC'"'
                if ( $SHRC_NO_GO == 0 ) then
                    echo '$GO is currently set to "'$GO'"'
                endif
                echo
                # Not really a "bad" end...
                goto bad_end
                breaksw
            case top:
                set BASE_DIR = $TOP
                breaksw
            case bin:
            case config:
                set BASE_DIR = "$TOP/$argv[1]"
                breaksw
            case doc:
            case Doc:
            case docs:
            case Docs:
                set BASE_DIR = "$TOP/Docs"
                breaksw
            case result:
            case results:
                set BASE_DIR = "$TOP/result"
                breaksw
            case int:
            case fp:
            case cpu:
                foreach suite ( `\ls "$TOP"/benchspec | grep CPU` )
                    if ( -d "$TOP"/benchspec/$suite ) then
                        set BASE_DIR = "$TOP"/benchspec/$suite
                        break
                    endif
                end
                breaksw
            case mpi:
                foreach suite ( `\ls "$TOP"/benchspec | grep MPI` )
                    if ( -d "$TOP"/benchspec/$suite ) then
                        set BASE_DIR = "$TOP"/benchspec/$suite
                        break
                    endif
                end
                breaksw
            case omp:
                foreach suite ( `\ls "$TOP"/benchspec | grep OMP` )
                    if ( -d "$TOP"/benchspec/$suite ) then
                        set BASE_DIR = "$TOP"/benchspec/$suite
                        break
                    endif
                end
                breaksw
            case src:
            case run:
            case data:
            case exe:
            case Spec:
                set argv = ( "" $argv )
            default:
                set BENCH = $argv[1]
                if ( $SHRC_NO_GO == 1 ) then
                    set ME = go
                else
                    set ME = ogo
                endif
                if ( $BENCH == "" ) then
                    # No benchmark specified; try to figure out what the current one
                    # (if any) is and Do The Right Thing.
                    # For the purposes of this exercise, try all of $TOP, $GO,
                    # and $SPEC.  It may be that the user is in an output root
                    # and wishes to indirectly visit a subdirectory in the main
                    # tree (or vice-versa).
                    # But in any case, don't pay attention to GO unless the
                    # user is using "ogo"
                    if ( $SHRC_NO_GO == 1 ) then
                      set GOGO=$SPEC
                    else
                      set GOGO=$GO
                    endif
                    foreach i ( "$TOP" "$GOGO" "$SPEC" )
                        set BENCH = `pwd | sed "s#$i//*benchspec/[^/][^/]*/##; s#/.*##;"`
                        if ( $BENCH != "" ) break
                    end
                    if ( $BENCH == "" ) then
                        # Give up
                        goto bad_end
                    endif
                endif
                foreach suite ( `\ls "$TOP"/benchspec` )
                    if ( ! -d "$TOP"/benchspec/$suite ) continue
                    if ( $debug ) echo Looking in suite \"$suite\"
                    # Found a suite; look for benchmarks
                    foreach bench ( `\ls "$TOP"/benchspec/$suite | grep "$BENCH"` )
                        if ( $debug ) echo Looking at benchmark \"$bench\"
                        if ( -d "$TOP"/benchspec/$suite/$bench ) then
                            # We have a winner
                            if ( $debug ) echo Chose \"$bench\"
                            set BASE_DIR = "$TOP"/benchspec/$suite/$bench
                            echo cd \"$BASE_DIR\" >>! /tmp/.gogo.$ppid
                            goto good_end
                        endif
                    end
                end
                echo Can\'t resolve \"$BENCH\" into a benchmark name
                echo
                echo Try \'$ME --help\' for options
                echo
                goto bad_end
            breaksw
        endsw
    endif
    echo cd \"$BASE_DIR\" >>! /tmp/.gogo.$ppid

good_end:
    if ( $#argv > 0 ) then
        # Try to change into other dirs
        shift
        foreach subdir ( $argv )
            if ( -d "$BASE_DIR"/$subdir ) then
                set BASE_DIR = "$BASE_DIR"/$subdir
                echo cd \"$subdir\" >>! /tmp/.gogo.$ppid
            else
                echo No directory named \"$subdir\"
                break
            endif
        end
    endif
    echo pwd >>! /tmp/.gogo.$ppid
    if ( $debug ) then
        echo Contents of /tmp/.gogo.$ppid follow:
        cat /tmp/.gogo.$ppid
    endif
    exit

bad_end:
    \rm -f /tmp/.gogo.$ppid

