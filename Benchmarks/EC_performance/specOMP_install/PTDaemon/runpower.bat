:: Windows batch file to run PTDaemon in power mode

:: See the Hardware Setup Guide for advanced configurations including GPIB usage

@echo off
echo.

:: Use a full path name for the ptd executable if it is not in the current directory
set PTDaemon=ptd-windows-x86.exe

:: Set NETWORK_PORT if needed.  8888 is the default used by benchmarks for the power device
set NETWORK_PORT=8888

:: Set DEVICE to the power analyzer device you will use (0=dummy device)
::  use the numeric value found in the help output of the PTDaemon executable
set DEVICE=0

:: Set DEVICE_PORT to the serial port you will connect your power analyzer to
set DEVICE_PORT=COM1


%PTDaemon% -p %NETWORK_PORT% %DEVICE% %DEVICE_PORT%

