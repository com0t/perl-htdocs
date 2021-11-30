#!/usr/bin/perl
#
##
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;
use Data::Dumper;
use File::Slurp;

my $args = shift;
$args =~ /^\'(.*)\'$/;
@ARGV = split(/\s/,$args);

my $operation	= shift;
my $assesscode	= shift;
my $status	= shift;	## only used by 'set'

riscUtility::loadenv();

chomp(my $psk = read_file("/etc/riscappliancekey"));

my $res;
if ($operation eq 'get') {
	eval {
		$res = riscConfigWeb::appliance_checkArchiveStatus($psk,$assesscode);
	}; if ($@) {
		print STDERR "$0: appliance_checkArchiveStatus() faulted: $@\n";
	}
	if (defined($res) and ($res->{'returnStatus'} =~ /success/i)) {
		print STDOUT join('&',1,$res->{'num'});
	} else {
		my $msg = 'An error has occurred -- please contact us through the community if this problem persists: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape';
		$msg = $res->{'returnStatusDetail'} if (($res) and ($res->{'returnStatusDetail'} !~ /java/));
		print STDOUT join('&',0,$msg);
	}
} elsif ($operation eq 'set') {
	eval {
		$res = riscConfigWeb::appliance_setArchiveStatus($psk,$assesscode,$status);
	}; if ($@) {
		print STDERR "$0: appliance_setArchiveStatus() faulted: $@\n";
	}
	if (defined($res) and ($res->{'returnStatus'} =~ /success/i)) {
		print STDOUT join('&',1,$res->{'returnStatusDetail'});
	} else {
		my $msg = 'An error has occurred -- please contact us through the community if this problem persists: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape';
		$msg = $res->{'returnStatusDetail'} if (($res) and ($res->{'returnStatusDetail'} !~ /java/));
		print STDOUT join('&',0,$msg);
	}
} else {
	print join('&',0,'invalid usage');
}

exit(0);
