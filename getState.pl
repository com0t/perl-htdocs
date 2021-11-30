#!/usr/bin/perl
use MIME::Base64;
use Data::Dumper;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

riscUtility::loadenv();

my ($user, $pass, $assessmentkey);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("3&Failed to decode arguments\n")) {
	($user, $pass, $assessmentkey) = map {
		$risc_credentials->{$_}
	} qw(user pass assessmentkey);
# the old fashioned way
} else {
	$user = decode_base64(shift);
	$pass = shift;
	$assessmentkey = shift;
}

my $problem = riscConfigWeb::testConnection();
my $status=riscConfigWeb::getAssessmentStats($user,$pass,$assessmentkey) if !defined $problem;

if ($status->{'status'} && !defined $problem ) {
	my $cStatusStatus = $status->{'status'};
	my $cStatusDetail = $status->{'statusdetail'};
	my $assessmentstate=$status->{'stage'};
	print "1&Successful&$assessmentstate\n" if $assessmentstate;
	print "0&$cStatusDetail\n" if not defined $assessmentstate;
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print "0&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}
