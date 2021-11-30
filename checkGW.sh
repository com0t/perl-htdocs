#!/bin/sh
#usage: checkGW.sh <ip> <sm> <dg>
#return: 1-succeeds or errorstring 

logfile="/var/log/interface/checkGW.log"

if [ $# -lt 3 ];then
	echo `date`" script called with incorrect arguments" >> $logfile
	echo 'Script error'
	exit 1
fi
IP="$1"
SM="$2"
DG="$3"

COUNT=$(ping -I $IP -c2 -w2 $DG|grep -oc "100%")
if [ $COUNT -ne 0 ]; then
	echo "Failed to ping Gateway($DG) from Interface($IP) with Subnet Mask($SM)"
else
	echo "1"
fi 

