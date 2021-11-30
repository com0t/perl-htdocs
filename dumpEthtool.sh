#!/bin/sh
#
## dumpEthtool.sh
##	runs ethtool on the interface with the specified port id (eth<n>)
##	dumps output to a file that is parsed by the frontend
#
## rewrite: 2015-10-16 colvin

logfile="/var/log/interface/dumpEthtool.log"
outputdir="/srv/httpd/htdocs/dump"

## populate interface variables
source /srv/httpd/htdocs/shell/popInterfaces.sh

## remove old dump file
[[ -f $outputdir/dumpEthtool.txt ]] && rm $outputdir/dumpEthtool.txt

n=0;
while [ $n -lt $numinterfaces ];do
	sudo ethtool ${interfaces[$n]} >> $outputdir/dumpEthtool.txt 2>> $logfile
	let n++
done

