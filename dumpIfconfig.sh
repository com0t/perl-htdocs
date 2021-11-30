#!/bin/sh
#
## dumpIfconfig.sh
##	gets the network interface information
##  dumps to text file parsed by frontend
#
## rewrite: colvin 2015-10-15

logfile="/var/log/interface/dumpIfconfig.log"
outputdir="/srv/httpd/htdocs/dump"

## remove old dump file
[[ -f $outputdir/dumpIfconfig.txt ]] && rm $outputdir/dumpIfconfig.txt

## get interfaces
source /srv/httpd/htdocs/shell/popInterfaces.sh

n=0
while [ $n -lt $numinterfaces ];do
	ip addr show dev ${interfaces[$n]} >> $outputdir/dumpIfconfig.txt 2>> $logfile
	let n++
done

