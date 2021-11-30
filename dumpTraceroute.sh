#!/bin/sh
#
## traceroute to risc services
## dump output to files parsed by frontend
#
## rewrite: colvin 2015-10-15

logfile="/var/log/interface/dumpTraceroute.log"
outputdir="/srv/httpd/htdocs/dump"

## orchestration service
traceroute orchestration.riscnetworks.com -w3 -m20 > $outputdir/dumpRouteOrchestration.txt 2>> $logfile
if [ $? -ne 0 ];then
	echo "ERROR: traceroute reported failure" > $outputdir/dumpRouteOrchestration.txt
fi

## initial service
traceroute initial.riscnetworks.com -w3 -m20 > $outputdir/dumpRouteInitial.txt 2>> $logfile
if [ $? -ne 0 ];then
	echo "ERROR: traceroute reported failure" > $outputdir/dumpRouteInitial.txt
fi

## dataup service
traceroute dataup.riscnetworks.com -w3 -m20 > $outputdir/dumpRouteDataup.txt 2>> $logfile
if [ $? -ne 0 ];then
	echo "ERROR: traceroute reported failure" > $outputdir/dumpRouteDataup.txt
fi

## debugging service
traceroute app1.riscnetworks.com -w3 -m20 > $outputdir/dumpRouteAPP1.txt 2>> $logfile
if [ $? -ne 0 ];then
	echo "ERROR: traceroute reported failure" > $outputdir/dumpRouteAPP1.txt
fi
