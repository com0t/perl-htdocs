#!/usr/bin/perl
#
## returns a string containing the logical name of the primary network interface
use strict;
use RISC::riscHost;

my $host = riscHost->new();
my $interface = $host->getPrimaryIF();
print $interface;
exit(0);
