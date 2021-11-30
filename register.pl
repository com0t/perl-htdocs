#!usr/bin/perl
use Data::Dumper;
use MIME::Base64;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

riscUtility::loadenv();

open (MYFILE,'>>/home/risc/soapFault');
my $time=time();

my ($user, $pass, $fName, $lName);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("0&Failed to decode arguments\n")) {
	($user, $pass, $fName, $lName) = map {
		$risc_credentials->{$_}
	} qw(user pass fName lName);
# the old fashioned way
} else {
	$user=decode_base64(shift);
	$pass=shift;
	$fName=decode_base64(shift);
	$lName=decode_base64(shift);
}

# unused in UI, but expected by the addUser endpoint
my ($phone, $email, $company, $street, $city, $state, $zip, $country) = ('', $user, '', '', '', '', '', '');

my $problem = riscConfigWeb::testConnection();

my $status = riscConfigWeb::addUser($user,$pass,$fName,$lName,$phone,$email,$company,$street,$city,$state,$zip,$country) unless $problem;

if ($status->{'status'} && !defined $problem ) {
	my $cStatus = $status->{'status'};
	my $cStatusUser = $status->{'userid'};
	my $cStatusDisplay = $status->{'statusdetail'};
	print "0&$cStatusDisplay&$cStatusUser\n" if $cStatus eq 'fail';
	print "1&$cStatusDisplay\n" if $cStatus eq 'success';
	print "1&$cStatusDisplay\n" if $cStatus eq 'userLinkUpdated';
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print MYFILE "$time -- FaultString:$errorString -- FaultDetail: $errorDetail -- FaultCode:$errorCode\n";
	print "2&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}

close (MYFILE);
