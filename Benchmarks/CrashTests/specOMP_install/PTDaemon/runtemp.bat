:: Windows batch file to run PTDaemon in temperature mode


:: See the Hardware Setup Guide for advanced configurations including GPIB usage

@echo off
echo.

:: 
:: NOTE: make sure your sensor is located properly -
::  "temperature must be measured no more than 50mm in front of (upwind of)
::     the main airflow inlet of the SUT"
::

echo NOTE: make sure your sensor is located properly - 
echo "temperature must be measured no more than 50mm in front of (upwind of)
echo  the main airflow inlet of the SUT"
echo.


:: Use a full path name for the ptd executable if it is not in the current directory
set PTDaemon=ptd-windows-x86.exe

:: Set NETWORK_PORT if needed.  8889 is the default used by benchmarks for the temperature sensor
set NETWORK_PORT=8889

:: Set DEVICE to the sensor device you will use (1000=dummy temp sensor)
::  use the numeric value found in the help output of the PTDaemon executable
set DEVICE=1000

:: Set DEVICE_PORT to the serial port you will connect your sensor to
set DEVICE_PORT=COM1


%PTDaemon% -t -p %NETWORK_PORT% %DEVICE% %DEVICE_PORT%

