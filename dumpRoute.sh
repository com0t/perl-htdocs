#!/bin/sh
#
## outputs the routing table
## dumps output to a file that is parsed by frontend
#
## rewrite: 2015-10-16 colvin

logfile="/var/log/interface/dumpRoute.log"
outputdir="/srv/httpd/htdocs/dump"

ip route show > $outputdir/dumpRoute.txt 2>> $logfile
