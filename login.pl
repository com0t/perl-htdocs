#!/usr/bin/perl
#
## login.pl -- performs user login to the appliance

use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;

## return codes
#	0	invalid
#	1	success
#	2	fault/error

riscUtility::loadenv();

my ($user, $pass);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("0&Failed to decode arguments\n")) {
	($user, $pass) = map {
		$risc_credentials->{$_}
	} qw(user pass);
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.*)\'$/;
	@ARGV = split(/\s/,$args);

	$user = decode_base64(shift);
	$pass = shift;
}

my $conn_error = riscConfigWeb::testConnection();
if ($conn_error) {
	print "3&$conn_error -- please check network settings on VM console or contact support\n";
	exit(1);
}

## authenticate the user
my $authentication = riscConfigWeb::auth_authenticateUser($user,$pass);
if (defined($authentication->{'returnStatus'})) {
	if ($authentication->{'returnStatus'} ne 'success') {
		my ($code,$detail) = split(/\|/,$authentication->{'returnStatusDetail'});
		print "0&$detail\n";
		exit(1);
	}
} else {
	print "2&An error has occurred during authentication -- please contact us through the community for assistance: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";
	exit(1);
}

## authorize the user
my $mysql = riscUtility::getDBH('risc_discovery');
my $assessmentcode = $mysql->selectrow_hashref("select productkey from credentials where technology = 'appliance' limit 1")->{'productkey'};
$mysql->disconnect();
if ($assessmentcode) {	## code has been entered
	riscConfigWeb::listAssessments($user,$pass);	## ensures pending invites are mapped in prior to authorization
	my $entitlement = riscConfigWeb::auth_getEntitlement($user,$pass,$assessmentcode);
	if (defined($entitlement->{'returnStatus'})) {
		if ($entitlement->{'returnStatus'} eq 'success') {
			print "1&".$authentication->{'returnStatus'}."&".$authentication->{'privLevel'}."\n";
		} else {
			my ($code,$detail) = split(/\|/,$entitlement->{'returnStatusDetail'});
			print "0&$detail\n";
			exit(1);
		}
	} else {
		print "2&An error has occurred during authorization -- please contact us through the community for assistance: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";
		exit(1);
	}
} else {		## no assessmentcode entered
	print "1&".$authentication->{'returnStatus'}."&".$authentication->{'privLevel'}."\n";
}

