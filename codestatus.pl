#!/usr/bin/perl
#
##
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;

## return codes
#	0	invalid/unauthorized
#	1	successful
#	2	demo
#	3	error/fault
my $invalid = 0;
my $success = 1;
my $demo = 2;
my $fault = 3;

riscUtility::loadenv();

my ($assessmentcode, $psk, $user, $pass);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("$fault&Failed to decode arguments\n")) {
	($assessmentcode, $psk, $user, $pass) = map {
		$risc_credentials->{$_}
	} qw(assessmentcode psk user pass);
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.*)\'$/;
	@ARGV = split(/\s/,$args);

	$assessmentcode = shift;
	$psk = shift;
	$user = decode_base64(shift);
	$pass = shift;
}

my $conn_error = riscConfigWeb::testConnection();
if ($conn_error) {
	print "$fault&$conn_error\n";
	exit(1);
}

if (length($assessmentcode) > 12) {	## valid code
	my $login = riscConfigWeb::auth_authenticateUser($user,$pass);
	if (defined($login->{'returnStatus'})) {
		if ($login->{'returnStatus'} eq 'success') {
			## authorization
			riscConfigWeb::listAssessments($user,$pass);	## ensures pending invites are mapped in prior to authorizing
			my $entitlement = riscConfigWeb::auth_getEntitlement($user,$pass,$assessmentcode);
			if (defined($entitlement->{'returnStatus'})) {
				if ($entitlement->{'returnStatus'} ne 'success') {
					my ($code,$detail) = split(/\|/,$entitlement->{'returnStatusDetail'});
					print "$invalid&$detail\n";
					exit(1);
				} ## else continue next block
			} else {
				print "$fault&An error has occurred during authorization -- please contact us through the community for assistance: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";
				exit(1);
			}
		} else {
			my ($code,$detail) = split(/\|/,$login->{'returnStatusDetail'});
			print "$invalid&$detail\n";
			exit(1);
		}
	} else {
		print "$fault&An error has occurred during authentication -- please contact us through the community for assistance: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";
		exit(1);
	}
} ## else demo

my $status = riscConfigWeb::codestatus($assessmentcode,$psk);

if (defined($status->{'returncode'})) {
	if ($status->{'returncode'} eq 'Valid') {
		print "$success&$status->{'nextsteps'}&$status->{'keycode'}\n";	## success
		exit(0);
	} elsif ($status->{'returncode'} =~ /demo/i) {
		print "$demo&$status->{'nextsteps'}\n";
		exit(0);
	} else {
		print "$invalid&$status->{'nextsteps'}\n";
		exit(1);
	}
} else {
	print "$fault&An error has occurred during code validation -- please contact us through the community for assistance: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";
	exit(1);
}

