#!/bin/sh
#

# set PTDaemon to PTDaemon executable path for your OS and installation location
PTDaemon=./ptd-linux-x86

# Set NETWORK_PORT if needed.  8888 is the default used by benchmarks for the power device
NETWORK_PORT=8888

# Set DEVICE to the power analyzer device you will use (0=dummy device)
DEVICE=0

# Set DEVICE_PORT to the serial port you will connect your power analyzer to
DEVICE_PORT=/dev/ttyS0


$PTDaemon -p $NETWORK_PORT $DEVICE $DEVICE_PORT