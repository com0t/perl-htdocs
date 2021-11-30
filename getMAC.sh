#!/bin/sh
#
# getMAC.sh eth*
# get MAC address of a port
# return 0-fails, MAC address-success
##

logfile="/var/log/interface/getMAC.log"

if [ -z "$1" ];then
	echo `date`" no interface index supplied" >> $logfile
	echo "0"
	exit 1
fi
iface="$1"

MAC=$(tr '[:lower:]' '[:upper:]' < "/sys/class/net/eth${iface}/address");
if [ "$MAC" ]; then
	echo $MAC
else
	echo "0"
fi
