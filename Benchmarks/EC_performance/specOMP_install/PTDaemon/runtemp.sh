#!/bin/sh
#
# NOTE: make sure your sensor is located properly - 
#  "temperature must be measured no more than 50mm in front of (upwind of)
#     the main airflow inlet of the SUT"
#

echo NOTE: make sure your sensor is located properly - 
echo  "temperature must be measured no more than 50mm in front of (upwind of)
echo     the main airflow inlet of the SUT"

# set PTDaemon to PTDaemon executable path for your OS and installation location
PTDaemon=./ptd-linux-x86

# Set NETWORK_PORT if needed.  8889 is the default used by benchmarks for the temperature device
NETWORK_PORT="8889"

# Set DEVICE to the temperature sensor device you will use (1000=dummy temperature sensor)
DEVICE="1000"

# Set DEVICE_PORT to the serial port you will connect your temperature sensor to
DEVICE_PORT="/dev/ttyS0"


$PTDaemon -t -p $NETWORK_PORT $DEVICE $DEVICE_PORT
