#!/usr/bin/perl
#
##
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;
use Data::Dumper;

my ($authuser, $authpass, $assesscode);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials('-1&Failed to decode arguments')) {
	($authuser, $authpass, $assesscode) = map {
		$risc_credentials->{$_}
	} qw(authuser authpass assesscode);
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.*)\'$/;
	@ARGV = split(/\s/,$args);

	$authuser = decode_base64(shift);
	$authpass = shift;
	$assesscode = shift;
}

riscUtility::loadenv();

my $res;
eval {
	$res = riscConfigWeb::isaLicensedCloudscape($authuser,$authpass,$assesscode);
}; if ($@) {
	print STDERR "$0: isaLicensedCloudscape() faulted: $@\n";
}
$res = -1 unless (defined($res));

if ($res == -1) {
	print STDOUT join('&',$res,'Unknown Assessment Type');
	exit(1);
} elsif ($res == 0) {
	print STDOUT join('&',$res,'HealthCheck');
} elsif ($res == 1) {
	print STDOUT join('&',$res,'CloudScape 1.0');
} elsif ($res == 2) {
	print STDOUT join('&',$res,'CloudScape 2.0');
}

exit(0);

