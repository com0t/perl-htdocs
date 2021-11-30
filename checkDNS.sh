#!/bin/sh
#
## do an dns lookup of the primary risc webservice
## return the string "1" on success
## return the error string on failure
#
## rewrite: 2015-10-16 colvin

## usage: checkDNS.sh <dns_server>

## service to look up for verification
webservice="orchestration.riscnetworks.com"

if [ -z "$1" ];then
	echo 'no dns server provided'
	exit 1
fi
dns="$1"

results=`nslookup $webservice $dns -timeout=1`
echo "$results" | grep 'timed out' &> /dev/null
if [ $? -eq 0 ];then
	echo $results	## print error we received
else
	echo "1"		## success
fi

