#!/usr/bin/perl
#
##
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;
use MIME::Base64;
use Data::Dumper;
use File::Slurp;

riscUtility::loadenv();

my $debugging = 0;
$debugging = $ENV{DEBUG} if (defined($ENV{DEBUG}));

my ($authuser, $authpass, $newcode);

# use environment to avoid logging any sensitive strings - this is run via sudo
if (my $risc_credentials = riscUtility::risc_credentials(sub { abrt('Failed to decode arguments') })) {
	($authuser, $authpass, $newcode) = map {
		$risc_credentials->{$_}
	} qw(authuser authpass newcode);
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.*)\'$/;
	@ARGV = split(/\s/,$args);

	($authuser, $authpass, $newcode) = @ARGV;

	$authuser = decode_base64($authuser);
}

unless (defined($authuser) and defined($authpass) and defined($newcode)) {
	abrt('Invalid usage -- contact help@riscnetworks.com');
}

my $origcode = riscUtility::getAssessmentCode();
if (!defined($origcode) or ($origcode =~ /demo/i)) {
	abrt('Cannot migrate: this appliance is not associated with an assessment');
}

my $db = riscUtility::getDBH('risc_discovery',1);
my $DB;
eval {
	$DB = riscUtility::getDBH('RISC_Discovery',1);
}; if ($@) {
	## if we can't connect to RISC_Discovery,
	## this should typically be the result of not having initialized the first time
	## if the DB is dead, we can't connect to little risc either, and the frontend to this won't work
	if ($@ =~ /unknown database/i) {
		abrt('Cannot migrate: a discovery scan has not been run');
	} else {
		abrt('An error has occurred<br/>contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-00');
	}
}

## the remap-redeviceid.pl script must exist
unless (-e '/home/risc/remap-redeviceid.pl') {
	abrt('Cannot migrate: contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-05');
}

## perform an allperf upload so we don't have stale perf
dbg('performing allperf upload');
`perl /home/risc/dataupload_modular_admin.pl allperf`;

## Get either the assessment code+mac (CentOS) or PSK for auth
dbg('building appliance mac or psk');

chomp(my $psk = read_file("/etc/riscappliancekey"));

## call the API to perform the reassociation
dbg('calling api');
my $reassoc = riscConfigWeb::appliance_reassociate_newAssessment($authuser,$authpass,$psk,$origcode,$newcode);
unless (($reassoc) and ($reassoc->{'returnStatus'} =~ /success/i)) {
	my $error;
	if ($reassoc) {
		$error = $reassoc->{'returnStatusDetail'};
		if ($error =~ /java/) {
			$error = 'An error has occurred<br/>contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-01';
		}
	} else {
		$error = 'An error has occurred<br/>contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-02';
	}
	abrt($error);
}
my $successmsg = $reassoc->{'returnStatusDetail'};

my $orig_assessid = $reassoc->{'orig_assessmentid'};
my $new_assessid = $reassoc->{'new_assessmentid'};

## update our assessmentcode from orig to new
dbg('replacing assessmentcode in db');
my $updatecode = $db->prepare("update credentials set productkey = ? where technology = 'appliance'");
$updatecode->execute($newcode);
$updatecode->finish();
dbg('replacing assessmentcode in file');
if (-e '/home/risc/dbbackup') {
	system('cp /home/risc/dbbackup /home/risc/dbbackup.remap');
}
system("echo '$newcode' > /home/risc/dbbackup");

## update apt repo credentials
dbg('updating apt repo credentials');
system('sed', '-i', "s|$origcode|$newcode|", '/etc/apt/auth.conf.d/risc.conf');

## kill the licensing
dbg('killing licensing');
eval { $DB->do('truncate table licensed'); };

## roll over the dataupload_modular_log table
dbg('rolling dataupload log');
eval {
	$DB->do('drop table if exists dataupload_modular_log_remap');
	$DB->do('create table dataupload_modular_log_remap like dataupload_modular_log');
	$DB->do('insert into dataupload_modular_log_remap select * from dataupload_modular_log');
	$DB->do('truncate table dataupload_modular_log');
}; if ($@) {
	abrt('An error has occurred<br/>contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-03');
}

## modify all deviceids to replace the assessmentid portion with the new assessmentid
unless (redeviceid($orig_assessid,$new_assessid)) {
	abrt('An error has occurred<br/>contact us through the community (https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape) and supply error code RNAPPMIG-04');
}

## finished
dbg('finished');
print STDOUT join('&',1,$successmsg);

$db->disconnect();
$DB->disconnect();
exit(0);

## the assessmentid is used as a portion of deviceids
## the assessmentid is supplied to the disco/inventory processes for this purpose, based on the current assessmentid
## there are several places where deviceids for existing devices are used for the purposes of uniqueness and correlation,
##   so if the assessmentid portion changes these processes will not function appropriately
## we need to modify all of the deviceids in current inventory to replace the assessmentid portion with the new assessmentid
## we do this in the remap-redeviceid.pl script, which is included in the scripts package
sub redeviceid {
	my ($old,$new) = @_;
	my $res = system("perl /home/risc/remap-redeviceid.pl $old $new");
	if ($res == 0) {
		return 1;
	} else {
		return 0;
	}
}

sub abrt {
	my ($msg) = @_;
	print STDOUT join('&',0,"$msg\n");
	exit(1);
}

sub dbg {
	my ($msg) = @_;
	print STDERR "$0: $msg\n" if ($debugging);
}

