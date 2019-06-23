@echo off
if not "%INSTALL_DEBUG%."=="." @echo on
rem
rem
rem  install.bat - installs SPEC benchmark or just tool binaries
rem  Copyright 1999-2011 Standard Performance Evaluation Corporation
rem
rem  Authors:  Bill Carr (CPU95 version)
rem            John Henning
rem            Cloyce D. Spradling
rem            Rahul Rahatekar
rem            Diego Esteves
rem  $Id: install.bat 73 2011-08-23 13:56:58Z BrianWhitney $
rem

set SUITE=omp2012
set SUITE_SIZE="~4500"

rem Currently the only platform that runs Windows are x86-compatible.
rem Currently the x86-64 and IA-64 systems also run the x86 tools.  So just
rem make sure CPU is set right:
set CPU=i386

if "%CPU%."=="." (
  echo The instance of Windows that you're running doesn't seem to set the
  echo CPU environment variable.  Please set it appropriately by hand.  For
  echo valid values, look in the \tools\bin directory on the distribution media.
  echo Toolsets for Windows have names like 'windows-i386'.
  echo For example, if you have an x86, x64, or IA-64 machine, you would
  echo .
  echo   set CPU=i386
  echo .
  echo Whereas if you have an Alpha NT system, you would
  echo .
  echo   set CPU=alpha
  echo .
  echo If there is no toolset for your processor, you will need to build the
  echo tools yourself.  In that case, set CPU to a reasonable value.
  echo .
  echo After setting the CPU environment variable, please re-run install.bat.
  goto bad_end
)

rem Insist on command extensions.  The "cd" will clear any
rem lingering error status ("color" does not!) and the color
rem command is only recognized if we have extensions enabled.
cd >nul:
color
if errorlevel 1 (
    echo .
    echo Sorry, we cannot build the tools unless you have command
    echo extensions enabled.  Please see "cmd /?" and "if /?".
    echo .
    goto bad_end
)
:efcmdext

if "%temp%."=="." (
    echo This install process will write several small temporary files.  Currently,
    echo the TEMP environment variable is not set.  Please set it to the full
    echo pathname of a directory where it's okay to write those files.  After
    echo that variable is set, please re-run install.bat.
    goto bad_end
)

rem This is a guess, but it should be a good one
set SPEC_VALID_ARCH=windows-%CPU%

rem Find top of benchmark install source
echo Installing FROM source: %~dp0
echo.
echo   If the source is NOT correct, hit Control-C and
echo   run install.bat from the correct benchmark tree.
echo.
pause
echo.

set SPEC=%~dps0

rem Figure out the destination directory

rem If less than two arguments are provided, the install is either in-place
rem (tools installation only) or there's one argument with drive and path;
rem either may be implicit
if "%~2." == "." goto new_style_args
CALL :set_full_path SPECNEW "%~1%~2"
CALL :check_dest_path "%~f0" "%SPECNEW%"
CALL :set_full_short_path SPECNEW "%~1%~2"
goto dest_set

:new_style_args
if "%~1." == "." goto implicit_destination
CALL :set_full_path SPECNEW "%~1"
CALL :check_dest_path "%~f0" "%SPECNEW%"
CALL :set_full_short_path SPECNEW "%~1"
goto dest_set

:implicit_destination
CALL :set_full_path SPECNEW "%CD%"
CALL :check_dest_path "%~f0" "%SPECNEW%"
CALL :set_full_short_path SPECNEW "%CD%"

:dest_set
rem See if there was an error making the destination directory; if there was,
rem check_dest_path will have cleared out %SPEC%
if "%SPEC%." == "." goto bad_end
set SPECNEW=%SPECNEW%\
echo.
echo.
echo Installing from "%SPEC%"
echo Installing to "%SPECNEW%"
echo.
echo.

rem Check to see if we are writable
CALL :set_full_short_path SPECNEWTMPFILE "%SPECNEW%\__SPEC__.TMP"
echo hello >"%SPECNEWTMPFILE%" 2>&1
if not exist %SPECNEWTMPFILE% (
    echo You seem to be installing from a CD or DVD.  Please re-run
    echo %0 and specify the destination path as the first argument.
    echo For example:   install c:\%SUITE%
    goto bad_end
)
del %SPECNEWTMPFILE%

rem Remove old tools installations (if any)
CALL :clean_tools %SPEC%
CALL :clean_tools %SPECNEW%

rem
rem Installation attempts begin here
rem
set SPECARCH=none

set TAR_VERBOSE=
set EXCLUDE_OPTS=
set EXCLUDE_PAT=
if "%VERBOSE%."=="." goto be_quiet
set TAR_VERBOSE=-v
:be_quiet

set DECOMPRESS=unset
set toolsbindir=%SPEC%\tools\bin\windows-%CPU%

if exist %toolsbindir%\specxz.exe (
  set DECOMPRESS=%toolsbindir%\specxz.exe
  set SPEC_VALID_ARCH=windows-%CPU%
  set INSTALL_DONT_COPY_TOOLS=TRUE
  set EXCLUDE_OPTS=%EXCLUDE_OPTS% --exclude=tools/*
  set EXCLUDE_PAT=%EXCLUDE_PAT% tools/

  set SPECARCH=%SPEC_VALID_ARCH%
)

if not "%INSTALL_DONT_COPY_BENCHSPEC%." == "." (
    set EXCLUDE_OPTS=%EXCLUDE_OPTS% --exclude=benchspec/*
    set EXCLUDE_PAT=%EXCLUDE_PAT% benchspec/
)

if "%SPECNEW%."=="%SPEC%." (
    set EXCLUDE_OPTS=%EXCLUDE_OPTS% --exclude=bin/* --exclude=config/* --exclude=Docs/* --exclude=Docs.txt/* --exclude=result/*
    rem bin/ is not excluded from checking because those files are not
    rem touched by the install process.
    set EXCLUDE_PAT=%EXCLUDE_PAT% config/ Docs/ Docs.txt/ result/
)

rem Since there are two possible sources for benchmark stuff (the big unified
rem tarball, or the individual tarballs), here's the selection algorithm:
rem - If SPEC_USE_UNIFIED is set to a nonempty value, try the big tarball
rem - If install_archives\release_control exists try to unpack the individual
rem     benchmark tarballs
rem - Otherwise, try the big tarball
rem If there's no install_archives directory, or if the install is running from
rem a Subversion working tree copy, lack of the big tarball will not cause
rem an abort; the tools will happily proceed to MD5 checking and tools
rem unpacking.  Otherwise, an error will be printed and the installation
rem aborted.

cd /d %SPECNEW%
set BENCHMARKS_UNPACKED=
if not "%SPECARCH%."=="none." (
  if "%SPEC_USE_UNIFIED%." NEQ "." goto unified
  if not exist "%SPEC%\install_archives\release_control" goto unified

:perbenchmark
  CALL :install_time_warning
  for /F "usebackq tokens=1,3*" %%i in ("%SPEC%\install_archives\release_control") do CALL :unpack_benchmark "%SPEC%\install_archives\benchball\%%i" %%j "%%k"
  set BENCHMARKS_UNPACKED=yes
goto check

:unified
  rem If there's no install_archives directory, it's not a CD/DVD, and so just
  rem skip to the check and the tools copy.
  if not exist "%SPEC%\install_archives" goto check
  rem If there's an install_archives directory and also a .svn directory, then
  rem it's a working tree copy.  Skip to the check and the tools copy.
  if exist "%SPEC%\.svn" goto check
  if not exist "%SPEC%\install_archives\%SUITE%.tar.xz" (
      echo.
      echo Can not find %SPEC%\install_archives\%SUITE%.tar.xz
      echo.
      echo The compressed suite image for %SUITE% is not present.  Aborting installation.
      goto bad_end
  )
  CALL :install_time_warning
  CALL :unpack_benchmark "%SPEC%\install_archives\%SUITE%.tar.xz" %SUITE_SIZE% "%SUITE% benchmark and data files"
  set BENCHMARKS_UNPACKED=yes

:check
  rem Only proceed with the installation if the benchmarks have been unpacked
  rem into %SPECNEW% _or_ it's supposed to be a tools-only installation.
  if not "%BENCHMARKS_UNPACKED%." == "." goto really_check
  if "%SPEC%" == "%SPECNEW%" goto really_check
  echo.
  echo There are no benchmark archives to unpack.  Please re-run the installation
  echo from a full copy of the media, or for a tools-only install, specify that
  echo the destination directory is the same as the source.
  echo.
  goto bad_end

:really_check
    echo %SPECARCH% > bin\packagename
    if "%SPEC_NO_CHECK%." == "." (
        echo.
        echo Checking the integrity of your source tree...
        echo.
        echo. Depending on the amount of memory in your system, and the speed of your
        echo. destination disk, this may take more than 10 minutes.
        echo. Please be patient.
        echo.
        type %SPEC%\MANIFEST > MANIFEST.tmp
        CALL :cull_manifest MANIFEST.tmp install_archives/
        rem Also remove things from the mnaifest that have been
        rem excluded from the tar
        for %%I in (%EXCLUDE_PAT%) DO CALL :cull_manifest MANIFEST.tmp %%I
        %toolsbindir%\specmd5sum -e -c MANIFEST.tmp > manifest.check.out
        if errorlevel 1 (
            findstr /V /R /C:": OK$" manifest.check.out
            del /F /Q MANIFEST.tmp >nul 2>&1
            echo Package integrity check failed!
            goto bad_end
        )
    )
    del /F /Q MANIFEST.tmp >nul 2>&1
    del manifest.check.out
    echo Unpacking tools binaries
    %DECOMPRESS% -dc %toolsbindir%\tools-%SPEC_VALID_ARCH%.tar.xz 2>NUL: > tmp-tools.tar
    %toolsbindir%\spectar %TAR_VERBOSE% -xf tmp-tools.tar
    del /F /Q tmp-tools.tar 
    
    echo Setting SPEC environment variable to %SPECNEW%
    set SPEC=%SPECNEW%
rem There's no Windows relocate, or it'd be run here
    if "%SPEC_NO_CHECK%." == "." (
        echo Checking the integrity of your binary tools...
        %toolsbindir%\specmd5sum -e -c SUMS.tools > toolcheck.out
        if errorlevel 1 (
            findstr /V /R /C:": OK$" toolcheck.out
            echo Binary tools integrity check failed!
            del /F /Q toolcheck.out >nul 2>&1
            goto bad_end
        )
    )
    goto end_build
)

rem So we don't have a pre-built executable. 
if not "%INSTALL_DEBUG%."=="." @echo on
rem Re-home ourselves
echo Setting SPEC environment variable to %SPECNEW%
set SPEC=%SPECNEW%
%SPECNEWDEV%
cd /d "%SPEC%"

rem Ask the question about compiling here so the person can go away
rem (hopefully) and let the thing install on it's own.
if "%SPECARCH%."=="none." (
    echo We do not appear to have vendor supplied binaries for your
    echo architecture.  You will have to compile specmake and specperl
    echo by yourself.  Please read \Docs\tools-build.txt and
    echo \tools\src\buildtools.bat.
    echo --------------------------------------------------------------
    echo If you wish I can attempt to build the tools myself.
    echo I'm not very intelligent so if anything goes wrong I'm just going
    echo to stop.
    echo If you do not hit CTRL-C *NOW*, I will attempt to execute the build.
    pause
)

%SPECNEWDEV%
rem Let buildtools worry about whether or not their build environment
rem works.
if not exist %SPEC%\tools\bin (
    echo Creating directory %SPEC%\tools\bin
    mkdir "%SPEC%\tools\bin"
)
if not exist %SPEC%\tools\bin\%SPEC_VALID_ARCH% (
    echo Creating directory %SPEC%\tools\bin\%SPEC_VALID_ARCH%
    mkdir "%SPEC%\tools\bin\%SPEC_VALID_ARCH%"
)

echo Running %SPECNEW%\tools\src\buildtools.bat
cd /d "%SPECNEW%\tools\src"
buildtools.bat

:end_build
del /F /Q toolcheck.out

:done
cd /d "%SPEC%"

rem Set up the environment as if for a run
set SHRC_COMPILER_PATH_SET=yes
set SHRC_QUIET=yes
call "%SPEC%"\shrc.bat
set SHRC_COMPILER_PATH_SET=
set SHRC_QUIET=

rem Run the runspec tests to make sure things are really okay
echo Testing the tools installation (this may take a minute)
call runspec --test > runspec-test.out 2>&1
if not errorlevel 1 goto test_ok
echo.
echo Error running runspec tests.
echo Search for "FAILED" in runspec-test.out for details.
echo.
goto bad_end

:test_ok
del runspec-test.out
echo.
echo Runspec tests completed successfully!

rem Check for WinZip munging
if exist %SPEC%\bin\test\WinZip.guard (
  %toolsbindir%\specmd5sum -e %SPEC%\bin\test\WinZip.guard > %temp%\winzip.test
  findstr /C:"1401a09c7fed3b499c79d987f1bf11e7" %temp%\winzip.test >nul 2>&1
  if not errorlevel 1 (
    del %temp%\winzip.test
    echo.
    echo.
    echo. It looks like WinZip has helpfully performed CR/LF conversion on files
    echo. it's extracted from the tarball.  Unfortunately, this has corrupted
    echo. most of the files in the distribution.
    echo. Please DISABLE the "Automatic CR/LF conversion for TAR files" in the
    echo. WinZip preferences before unpacking the distribution tarball, or
    echo. preferably, use specxz and spectar to unpack the distribution.
    echo. You can find them in
    echo.   %toolsbindir%
    echo.
    echo.
    goto bad_end
  )
)

goto good_end

:cull_manifest
rem This is how to get multiple commands into a FOR loop.  Geez.
rem The name of the file to cull is in %1, and the strings that should
rem be removed are in %2.
findstr /V /C:" %2" %1 > %SUITE%.cull.filetemp
del /F /Q %1
rename %SUITE%.cull.filetemp %1
goto :EOF

:unpack_benchmark
rem This unpacks the file in %1
echo Unpacking %~3 (%~2 MB)
%DECOMPRESS% -dc "%1" 2>NUL: > tmp-bmark.tar
%toolsbindir%\spectar %EXCLUDE_OPTS% %TAR_VERBOSE% -xf tmp-bmark.tar
del /F /Q tmp-bmark.tar 
goto :EOF

:install_time_warning
echo.
echo. Depending on the speed of the drive holding your installation media
echo. and the speed of your destination disk, this may take more than 5 minutes.
echo. Please be patient.
echo.
goto :EOF

:set_full_dir_name
rem Variable in %1, value in %2
set %1=%~dp2
goto :EOF

:set_full_path
rem Variable in %1, value in %2
set %1=%~f2
goto :EOF

:set_full_short_path
rem Variable in %1, value in %2
set %1=%~fs2
goto :EOF

:check_dest_path
rem Candidate destination path in %2, path to install.bat in %1
echo Installing TO destination: %2
echo.
echo    If the destination is NOT correct, hit Control-C and
echo    specify the desired installation path as a parameter.
echo    For example:
echo.
echo    %~1  D:\SPEC\%SUITE%
echo.
pause
rem Make sure that the directory exists
if exist "%~f2" goto :dir_exists
mkdir "%~f2"
if errorlevel 1 (
    echo There was an error creating the %~f2 directory.
    goto clear_all
)
:dir_exists
goto :EOF

:clean_tools
set CHECKDIR=%1
set QUIET=%2
if exist %CHECKDIR%\bin\specperl.exe goto toolsinst
if exist %CHECKDIR%\SUMS.tools goto toolsinst
if exist %CHECKDIR%\bin\lib goto toolsinst
set CHECKDIR=
goto :EOF
:toolsinst
if "%QUIET%."=="." (
    echo Removing previous tools installation in %CHECKDIR%
)
rem The one-line equivalent under Unix turns into this hack to write a batch
rem file and then call it.  At least we can build the batch file using Perl...
if exist %CHECKDIR%\bin\specperl.exe (
    if exist %temp%\toolsdel.bat del /F /Q %temp%\toolsdel.bat
    %CHECKDIR%\bin\specperl.exe -ne "@f=split; next unless m#bin/#; $_=$f[3]; s#^#$ENV{CHECKDIR}/#; s#\\#/#g; for(my $i = 0; $i < 2; $i++) { if (-f $_) { unlink $_; } elsif (-d $_) { s#/#\\#g; print """rmdir /Q /S $_\n"""; } s#\.exe$##; }" %CHECKDIR%\SUMS.tools > %temp%\toolsdel.bat
    call %temp%\toolsdel.bat
    del /F /Q %temp%\toolsdel.bat
    rem Now fall through in case some things were missed by toolsdel.bat
)
rem Now make a non-Perl-based best effort to remove things.
rmdir /Q /S %CHECKDIR%\bin\lib
del   /Q /F %CHECKDIR%\bin\*.exe
del   /Q /F %CHECKDIR%\bin\*.dll
del   /Q /F %CHECKDIR%\SUMS.tools
del   /Q /F %CHECKDIR%\bin\packagename
if "%QUIET%."=="." (
    echo Finished removing old tools install
)
set CHECKDIR=
goto :EOF

:bad_end
rem Remove any tools installations that might've happened
CALL :clean_tools %SPEC% 1
CALL :clean_tools %SPECNEW% 1
echo Installation NOT completed!
goto clear_all

:good_end
echo Installation completed!
goto clear_all

:clear_all
set SUITE=
set SUITE_SIZE="~4500"
set SPEC=
set SPECARCH=
set SPECNEW=
set SPECNEWDEV=
set SPECNEWPATH=
set SPECNEWTMPFILE=
set SPEC_MAKE_LEVEL=
set SPEC_PERL_LEVEL=
set SPEC_VALID_ARCH=
set SPECPERLLIB=
set INSTALL_DONT_COPY_TOOLS=
set EXCLUDE_OPTS=
set EXCLUDE_PAT=
set TAR_VERBOSE=
goto :EOF
