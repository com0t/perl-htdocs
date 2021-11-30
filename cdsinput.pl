#!/usr/bin/perl
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

riscUtility::loadenv();

my ($authUser, $authPass, $assessmentcode);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("0&Failed to decode arguments\n")) {
	($authUser, $authPass, $assessmentcode) = map {
		$risc_credentials->{$_}
	} qw(authUser authPass assessmentcode);
# the old fashioned way
} else {
	($authUser, $authPass, $assessmentcode) = (shift, shift, shift);
}

#This script pushes the CDS information from the local appliance to the web service so that it is immediately available.
my $custFirst = shift;
my $custLast = shift;
my $custCCO = shift;
my $custEmail = shift;
my $state = shift;
my $partFirst = shift;
my $partLast = shift;
my $partEmail = shift;
my $partCCO = shift;
my $partCCOPass=shift;
my $market=shift;
my $vertical = shift;
my $addedby = $authUser;

#Here we need to set any variables to 'none' if they are not defined.
$custFirst='none' unless $custFirst;
$custLast='none' unless $custLast;
$custCCO='none' unless $custCCO;
$custEmail='none' unless $custEmail;
$state='none' unless $state;
$partFirst='none' unless $partFirst;
$partLast='none' unless $partLast;
$partCCO='none' unless $partCCO;
$partCCOPass='none' unless $partCCOPass;
$market='none' unless $market;
$vertical='none' unless $vertical;
$partEmail='none' unless $partEmail;
$addedby='none' unless $addedby;

my $problem = riscConfigWeb::testConnection();
my $status = riscConfigWeb::updateCDSInfo($authUser,$authPass,$assessmentcode,$partFirst,$partLast,$partEmail,$partCCO,$partCCOPass,$market,$vertical,$addedby,$custFirst,$custLast,$custCCO,$custEmail,$state) if !defined $problem;

if ($status->{'assessmentid'} && !defined $problem && $status->{'assessmentid'} != 0) {
	print "1&UpdateSuccessful&CDS Information has been updated\n";
} elsif ($status->{'assessmentid'} == 0){
	print "0&CDS Information was not updated Properly.  Please try again\n";
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print "0&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}
