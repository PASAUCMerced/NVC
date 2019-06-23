@echo off
rem
rem shrc.bat
rem
rem   This file sets up your path and other environment variables for SPEC OMP
rem
rem   --> YOU MUST EDIT THIS FILE BEFORE USING IT <--
rem    
rem   SPEC OMP benchmarks are supplied as source code (C, C++, Fortran).  
rem   They must be compiled before they are run.
rem
rem    1. If someone else compiled the benchmarks, you need
rem       to edit just one line in this file.  To find it, 
rem       search for:
rem                    "Already Compiled"
rem
rem    2. If you are compiling the benchmarks, you need to change
rem       two parts of this file.  Search for *all* the places
rem       that say:
rem                    "My Compiler"
rem
rem    Usage: do the edits, then:
rem           cd <specroot>
rem           shrc
rem
rem Authors: J.Henning, Cloyce Spradling
rem
rem Copyright (C) 1999-2011 Standard Performance Evaluation Corporation
rem  All Rights Reserved
rem
rem $Id: shrc.bat 75 2011-08-23 14:13:46Z BrianWhitney $
rem ---------------------------------------------------------------

rem ================
rem Already Compiled
rem ================
rem        If someone else has compiled the benchmarks, then the 
rem        only change you need to make is to uncomment the line 
rem        that follows - just remove the word 'rem'

rem set SHRC_PRECOMPILED=yes

rem ==================
rem My Compiler Part 1
rem ==================
rem      If you are compiling the benchmarks, you need to *both* 
rem       - set your path, at the section marked "My Compiler Part 2"
rem       - *and* uncomment the next line (remove the word "rem")

rem set SHRC_COMPILER_PATH_SET=yes

rem ---------------------------------------------------------------
rem
if "%SHRC_COMPILER_PATH_SET%x"=="yesx" goto SHRC_compiler_path_set
if "%SHRC_PRECOMPILED%x"=="yesx"       goto SHRC_compiler_path_set
echo Please read and edit shrc.bat before attempting to execute it!
goto :EOF

:SHRC_compiler_path_set

rem ==================
rem My Compiler Part 2
rem ==================
rem  A few lines down (at "BEGIN EDIT HERE"), insert commands that 
rem  define the path to your compiler.  There are two basic options:
rem     - Option A (usually better): call a vendor-supplied batch file, or 
rem     - Option B: directly use the "set" command.  
rem
rem  WARNING: Do not assume that examples below will work as is.  
rem  These files change frequently.  Use the examples to help you
rem  understand what to look for in your compiler documentation.
rem 
rem  Option A.  Examples of vendor path .bat files:
rem   call "c:\program files\Intel\Compiler\C++\9.1\IA32\Bin\iclvars.bat"
rem   call "C:\Program Files (x86)\Intel\ComposerXE-2011\bin\compilervars.bat" ia32
rem   call "C:\Program Files (x86)\Microsoft Visual Studio 10.0\Common7\Tools\vsvars32.bat"
rem   call "c:\program files\microsoft visual studio 8\Common7\Tools\vsvars32.bat"
rem   call "c:\program files\microsoft visual studio .NET 2003\Vc7\Bin\vcvars32.bat"
rem   call "c:\Program Files\PGI\win64\11.7\pgi_env.bat"
rem   call "c:\Program Files (x86)\PGI\win32\11.7\pgi_env.bat"
rem
rem  Option B.  Examples of setting the path directly:
rem    set PATH=%PATH%;"c:\program files\microsoft visual studio\vc98\bin"
rem    set PATH=%PATH%;"c:\program files\microsoft visual studio\df98\bin"
rem  Note that you may also need to set other variables, such as LIB and 
rem  INCLUDE.  Check your compiler documentation.
rem
rem XXXXXXXX BEGIN EDIT HERE XXXXXXXXXXX
rem   Call .bat or set PATH here.  Warning: no semicolons inside quotes! 
rem   http://www.spec.org/cpu2006/docs/faq.html#Build.02
rem XXXXXXXX END EDIT HERE XXXXXXXXXXX

rem set SPEC environment variable
rem

rem if the SPEC variable is set, and it points to something that looks
rem reasonable, then use that, otherwise fall through
if not "%SPEC%."=="." goto SPEC_env_not_defined
if exist %SPEC%\bin\runspec goto SPEC_env_defined
:SPEC_env_not_defined

rem we don't search the directory path, so you have to be in the top level
rem of the SPEC tree for this to work
if not exist bin\runspec (
    echo You are not in the top level of the SPEC directory!
    goto :EOF
)

rem go ahead and fetch the path, thanks to Diego.
CALL :set_short_path SPEC %CD%

:SPEC_env_defined
rem at this point SPEC should point to the correct stuff, so set up the
rem rest of the environment.
set SPECPERLLIB=%SPEC%\bin;%SPEC%\bin\lib;%SPEC%\bin\lib\site
echo "%PATH%" > %temp%\specpath.txt
CALL :add_path %SPEC%\bin %temp%\specpath.txt
CALL :add_path %SPEC%\bin\windows %temp%\specpath.txt
del /f /q %temp%\specpath.txt

if not "%SHRC_QUIET%."=="." goto :EOF

rem    Finally, let's print all this in a way that makes sense.  
rem    While we're at it, this is a good little test of whether 
rem    specperl is working for you!

specperl bin\printpath.pl

goto :EOF

:add_path
rem If the find from SFU is called, it'll spew some warnings, but the only
rem effect is that %1 will always be added to the PATH.  IOW, a fail safe.
find /I "%1" %2 > nul 2>&1
if errorlevel 1 set PATH=%1;%PATH%
goto :EOF

:set_short_path
rem Variable in %1, path in %2.  If only cmd would allow the ~ modifiers on
rem regular variables!
set %1=%~fs2
goto :EOF
