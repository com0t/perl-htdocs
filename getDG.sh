#!/bin/sh
#
# getDG.sh
# get default gateway of eth1 for vitural appliance 
# return 0-fails, default gateway-success
##

DG=$(ip route show|grep 'default'|cut -d' ' -f3); 

if [ $DG ]; then
	echo $DG;
else
	echo "0";
fi

