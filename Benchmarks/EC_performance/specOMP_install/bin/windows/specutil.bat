@echo off
rem
rem specutil.bat - run SPEC Perl tools from Microsoft Windows Command Prompt
rem
rem  Copyright 2008 Standard Performance Evaluation Corporation
rem   All Rights Reserved
rem
rem  Author:  Diego Esteves
rem
rem $Id: specutil.bat 4 2008-06-26 14:09:58Z cloyce $
rem
rem ======================================================================
rem
rem %1   - Name of utility to run (must reside in %SPEC%\bin)
rem %2-* - arguments to specified utility
rem
rem ======================================================================

rem
rem Don't do anything if nothing specified
rem
if %1. == . goto :EOF

rem
rem Make sure SPEC is defined - it should've already been set
rem
if NOT defined SPEC goto shrc_warning
if NOT exist "%SPEC%\bin\runspec" goto shrc_warning
goto run_program

:shrc_warning

    echo.
    echo ***WARNING***
    echo The environment variable SPEC should point to the source of the
    echo benchmark distribution as an absolute path.  Please use shrc.bat
    echo to set this variable.
    echo ***WARNING***
    echo.
    goto :EOF

:run_program

rem
rem Let's run program
rem - do not run copy in current directory- run it only from %SPEC%\bin
rem

if not exist %SPEC%\bin\%1 (
  echo.
  echo ***ERROR***
  echo Program '%1' does NOT exist in directory '%SPEC%/bin'.
  goto :EOF
)

specperl %SPEC%\bin\%*
exit /B %ERRORLEVEL%
