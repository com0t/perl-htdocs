#!/bin/sh
#usage: checkPort.sh portId(0-5)
#return: 1(partial/ok) or 0(down)

logfile="/var/log/interface/checkPort.log"

if [ -z "$1" ];then
	echo `date`" no interface ID provided" >> $logfile
	echo "0"
	exit 1
fi
PORTID="$1"

STATUS=`sudo ethtool eth$PORTID | grep "Link detected" | cut -d ":" -f2 | tr -d " "`
if [ "$STATUS" = "yes" ]; then
	echo "1";
else
	echo `date`" interface eth${PORTID} is down" >> $logfile
	echo "0"
fi

