#!/usr/bin/perl
#
##
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;
use Data::Dumper;
use File::Slurp;

## accepts a directive and the assessment code
## the directive is either 'get' or 'set'

## returns <success>&<detail>
## success is either 1 for success or 0 for fail
## for get, if success, detail is the status of the EULA, where 0 is unaccepted and 1 is accepted
## for set, if success, detail is the returnStatus string
## if fail, detail is the returnStatusDetail failure string

my $args = shift;
$args =~ /^\'(.*)\'$/;
@ARGV = split(/\s/,$args);

my $operation	= shift;
my $assesscode	= shift;

riscUtility::loadenv();

chomp(my $psk = read_file("/etc/riscappliancekey"));

my $res;
if ($operation eq 'get') {
	eval {
		$res = riscConfigWeb::appliance_checkEulaStatus($psk,$assesscode);
	}; if ($@) {
		print STDERR "$0: appliance_checkEulaStatus() faulted: $@\n";
	}
	if (defined($res) and ($res->{'returnStatus'} =~ /success/i)) {
		print STDOUT join('&',1,$res->{'num'});
	} else {
		my $msg = 'an error has occurred -- please contact us through the community if this problem persists: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape';
		$msg = $res->{'returnStatusDetail'} if ($res);
		print STDOUT join('&',0,$msg);
	}
} elsif ($operation eq 'set') {
	eval {
		$res = riscConfigWeb::appliance_setEulaStatus($psk,$assesscode);
	}; if ($@) {
		print STDERR "$0: appliance_setEulaStatus() faulted: $@\n";
	}
	if (defined($res) and ($res->{'returnStatus'} =~ /success/i)) {
		print STDOUT join('&',1,$res->{'returnStatusDetail'});
	} else {
		my $msg = 'an error has occurred -- please contact us through the community if this problem persists: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape';
		$msg = $res->{'returnStatusDetail'} if ($res);
		print STDOUT join('&',0,$msg);
	}
} else {
	print join('&',0,'invalid usage');
}

exit(0);

