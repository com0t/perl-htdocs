#!usr/bin/perl
use MIME::Base64;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

riscUtility::loadenv();

my ($user, $pass, $assessmentkey, $messageDetail);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("3&Failed to decode arguments\n")) {
	($user, $pass, $assessmentkey, $messageDetail) = map {
		$risc_credentials->{$_}
	} qw(user pass assessmentkey messageDetail);
# the old fashioned way
} else {
	my $args = shift;
	$args =~/^\'(.+)\'$/;
	@ARGV = split(/\s/, $args);

	$user = decode_base64(shift);
	$pass = shift;
	$assessmentkey = shift;
	$messageDetail = shift;
}

my $messageType = 'Invitation';
my $conf = 0;

#call notfication webservice
my $problem = riscConfigWeb::testConnection();

my $status = riscConfigWeb::addLog($user,$pass,$assessmentkey,$messageType,$messageDetail,$conf) if !defined $problem;

if ($status->{'messagedetail'} && !defined $problem ) {
	my $cStatus = $status->{'messagedetail'};
	print "1&Successful&An invitation has been sent to $messageDetail\n";
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print "0&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}
