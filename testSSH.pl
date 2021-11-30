#!/usr/bin/env perl
#
##
use strict;
use MIME::Base64 qw(decode_base64);
use RISC::CiscoCLI;
use RISC::riscUtility;
use File::Temp qw(tempfile);
$|++;

my ($trans, $user, $pass, $ena, $host);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials('0:Failed to decode credentials')) {
	($trans, $user, $pass, $ena, $host) = map {
		$risc_credentials->{$_}
	} qw(trans user pass ena host);
# the old fashioned way
} else {
	$trans = decode_base64(shift);
	$user = decode_base64(shift);
	$pass = decode_base64(shift);
	$ena = decode_base64(shift);
	$host = decode_base64(shift);
}

my $result;

my $logfile = (tempfile(UNLINK => 1))[1];
if ($trans eq 'ssh') {
        $result = RISC::CiscoCLI::checkCLISSH($host, $user, $pass, $ena, $logfile);
} elsif ($trans eq 'telnet') {
        $result = RISC::CiscoCLI::checkCLITelnet($host, $user, $pass, $ena, $logfile);
} else {
        print "0:Invalid transport";
}

if ($result) {
        print $result;
} else {
        print "0:Unknown connection error";
}
