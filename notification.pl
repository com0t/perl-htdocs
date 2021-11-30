#!usr/bin/perl
#use SOAP::Lite +trace=>"debug";
use MIME::Base64;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

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

riscUtility::loadenv();

#call notfication webservice
my $noteType = shift;
my $noteDetail = shift;
my $desc = decode_base64(shift);

my $status = riscConfigWeb::notify($user,$pass,$assessmentkey,$noteType,$noteDetail,$desc);
#print Dumper($status);
if ($status->{'outputmessage'}) {
	my $cStatus = $status->{'outputmessage'};
	print "1&Successful&$cStatus\n";
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print "0&$errorString\n";
}
