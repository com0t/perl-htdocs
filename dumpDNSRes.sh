#!/bin/sh
#
## dumpDNSRes.sh
##	resolves the risc services from the user-supplied DNS server
##	dumps the results into text files for processing from the front-end
#
## rewrite: colvin 2015-10-15

## USAGE
#
## dumpDNSRes.sh <dns server>

## error log
logfile="/var/log/interface/dumpDNSRes.log"

## output directory
outputdir="/srv/httpd/htdocs/dump"

## ensure we got a DNS server argument
if [ -z "$1" ];then
	echo `date`"  script called without DNS argument or null DNS argument" >> $logfile
	echo "ERROR: no DNS server configured" > $outputdir/dumpDNSorchestration.txt
	echo "ERROR: no DNS server configured" > $outputdir/dumpDNSinitial.txt
	echo "ERROR: no DNS server configured" > $outputdir/dumpDNSdataup.txt
	echo "ERROR: no DNS server configured" > $outputdir/dumpDNSapp1.txt
	exit 1
fi

## get DNS server argument
DNS="$1"

## check for shell injection
echo "$DNS" | grep -e ';' -e ' ' &> /dev/null
if [ $? -eq 0 ];then
	echo `date`"  shell injection detected in DNS server argument" >> $logfile
	exit 2
fi

## orchestration service
nslookup orchestration.riscnetworks.com $DNS -timeout=1 > $outputdir/dumpDNSorchestration.txt 2>> $logfile

## initial service
nslookup initial.riscnetworks.com $DNS -timeout=1 > $outputdir/dumpDNSinitial.txt 2>> $logfile

## data upload service
nslookup dataup.riscnetworks.com $DNS -timeout=1 > $outputdir/dumpDNSdataup.txt 2>> $logfile

## debugging service
nslookup app1.riscnetworks.com $DNS -timeout=1 > $outputdir/dumpDNSapp1.txt 2>> $logfile

exit 0
##

