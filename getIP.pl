#!/usr/bin/perl
#
## getIP.pl
#
## returns a string of network configuration information
## replaces the old getDHCP.sh
#
## params:
#		index (interface index)
##
use strict;
use Data::Dumper;
use RISC::riscHost;

my $index = shift;

my $host = riscHost->new();

my $intf = 'eth' . $index;

my $ipinfo = $host->getIFInfo($intf);

if (defined($ipinfo->{addr})) {
	printf("%s:%s:%s:%s",$ipinfo->{addr},$ipinfo->{mask},$ipinfo->{gateway},$ipinfo->{dns});
} else {
	print "0";
}
##