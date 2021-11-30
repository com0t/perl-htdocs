#!/bin/sh
#
## dumpApplianceVersion.sh
##  gets the appliance version from /etc/riscrevision
##	dumps the results into text files for processing from the front-end

## error log
logfile="/var/log/interface/dumpApplianceVersion.log"

## output directory
outputdir="/srv/httpd/htdocs/dump"

if [ -f /etc/riscrevision ];then
	cat /etc/riscrevision > $outputdir/dumpApplianceVersion.txt
else
	echo "Unable to determine appliance version" > $outputdir/dumpApplianceVersion.txt
	echo `date`" /etc/riscrevision not found" >> $logfile
fi
