#!/usr/bin/perl
#
## setPort.pl
#
## uses RISC::riscHost to set a network interface configuration
## replaces older setPort.sh for CentOS appliances
## parameters:
#		index:ip:mask:gateway:dns
#	OR
#		index:dhcp
##
use strict;
use Data::Dumper;
use RISC::riscHost;

my $args = shift;
my @args = split(/:/,$args);
my $indx = $args[0];
my $addr = $args[1];
my $mask = $args[2];
my $gate = $args[3];
my $name = $args[4];

my $host = riscHost->new();

my $intf = 'eth' . $indx;

my $setip;
if ($addr eq 'dhcp') {
	$setip = $host->applyIP($intf,'dhcp');
} else {
	$setip = $host->applyIP($intf,$addr,$mask,$gate,$name);
}

if ($setip->{returnStatus} == 1) {
	print "1";
} else {
	print "0";
}
##