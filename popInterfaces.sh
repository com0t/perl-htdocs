#!/bin/sh
#
## utility script for use by other shell scripts
## source this script to instantiate an array of interface names and a count of interfaces
## once sourced, the variables:
##    interfaces[]
##    numinterfaces
## will be available to the client script
#
## usage: source /srv/httpd/htdocs/shell/getInterfaces.sh

n=0;
ip link show | grep 'eth[0-9]' | cut -d' ' -f2 | cut -d':' -f1 > /tmp/interfaces
while read line; do
	interfaces[$n]="$line"
	let n++
done < /tmp/interfaces
numinterfaces="$n"
rm /tmp/interfaces
