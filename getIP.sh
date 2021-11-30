#!/bin/sh
#
# getIP.sh
# get IP address of eth0 for vitural appliance 
# return 0-fails, IP address-success
##

IP=$(ifconfig|grep 'inet '|fgrep -v 127.0.0.1| awk 'NR==1{print $2}');

if [ $IP ]; then
	echo $IP
else
	echo "0"
fi
