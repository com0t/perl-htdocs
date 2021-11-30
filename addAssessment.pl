#!usr/bin/perl
use Data::Dumper;
use MIME::Base64;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

riscUtility::loadenv();

open (MYFILE,'>>/home/risc/soapFault');

my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

my ($user, $pass, $assessmentkey, $psk);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("3&Failed to decode arguments\n")) {
	($user, $pass, $assessmentkey, $psk) = map {
		$risc_credentials->{$_}
	} qw(user pass assessmentkey psk);
# the old fashioned way
} else {
	$user = decode_base64(shift);
	$pass = shift;
	$assessmentkey = shift;
	$psk = shift;
}

my $time=time();
my $company=decode_base64(shift);
my $street=decode_base64(shift);
my $city=decode_base64(shift);
my $state=decode_base64(shift);
my $zip=decode_base64(shift);
my $country=decode_base64(shift);
my $startdate=decode_base64(shift);
my $problem=riscConfigWeb::testConnection();

my $status=riscConfigWeb::addAssessment($user,$pass,$assessmentkey,$psk,$company,$street,$city,$state,$zip,$country,$startdate) unless $problem;

#Check to see if we are good or not
if ($status->{'status'} && !defined $problem ) {
	my $cStatus = $status->{'status'};
	my $cStatusDetail = $status->{'statusdetail'};
	print "0&$cStatusDetail\n" if $cStatus eq 'Invalid';
	print "0&Assessment already added for this appliance" if $cStatus eq 'Valid';
	print "1&Successful in Demo Mode\n" if $cStatus eq 'Demo';
	print "1&$cStatus&$cStatusDetail\n" if $cStatus eq 'SUCCESS';
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print MYFILE "$time -- FaultString:$errorString -- FaultDetail: $errorDetail -- FaultCode:$errorCode\n";
	print "3&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}

close (MYFILE);
