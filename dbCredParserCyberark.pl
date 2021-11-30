#!/usr/bin/perl
#
## validate, parse, and import DB creds from csv

use strict;
use RISC::riscUtility;
use Time::HiRes;
use Data::Dumper;
use Net::IP;
use Text::CSV;
use MIME::Base64;

# knobs
########
my $debugging	= 0;	## produce debugging output on STDERR
my $noop	= 0;	## just parse, don't insert anything

my ($infilepath, $query_string, $context, $noop_arg);

# take in file path and Cyberark query string
# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials(sub { abort('Failed to decode arguments') })) {
	($infilepath, $query_string, $context, $noop_arg) = map {
		$risc_credentials->{$_}
	} qw(infilepath query_string context noop_arg);
# the old fashioned way
} else {
	($infilepath, $query_string, $context, $noop_arg) = map { decode_base64($_) } @ARGV;
}

my $tech = 'db';
my $removed = 0;

unless ($infilepath) {
	abort("No file provided");
}
unless (-e $infilepath) {
	abort("No such file: $infilepath");
}
unless ($query_string) {
	abort("No query string provided");
}
unless ($context) {
	abort("No database type provided");
}

# initialize Text::CSV
my $csv = Text::CSV->new({sep_char => ','});

my $db = riscUtility::getDBH('risc_discovery',1);

## optional second argument overrides the noop knob
## if set and true, set noop --> 1
## if set and false (0), set noop --> 0

if (defined($noop_arg)) {
	if ($noop_arg) {
		$noop = 1;
	} else {
		$noop = 0;
	}
}

my $infile;
unless(open($infile,"<",$infilepath)) {
	abort("Could not open file");
}

my @rows;
my $ip_count = 0;

while (my $row = $csv->getline($infile)) {
    my ($ip, $port) = @$row;
    # IP Validation Steps
    my $ip_obj = Net::IP->new($ip);
    if (!$ip_obj) {
        my $error = 'not an ip: ' . Net::IP::Error();
        logmsg($error);
        abort($error);
    }
    my $normalized = $ip_obj->ip();
    if ($ip ne $normalized) {
        my $error = 'not an ip: ' . $ip;
        logmsg($error);
        abort($error);
    }
    if (!length($port) || $port !~ /^\d+$/ || $port < 1 || $port > 65535) {
        my $error = 'invalid port: ' . $port;
        logmsg($error);
        abort($error);
    }
    my $qs = $query_string;
    $qs =~ s/IP_ADDRESS_PLACEHOLDER/$ip/;
    push(@rows, [$ip, $port, $context, $tech, $removed, $qs]);
    $ip_count++;
}

$csv->eof or do {
    my $error = 'csv parsing failed: ' . $csv->error_diag();
    logmsg($error);
    abort($error);
};

if ($ip_count == 0) {
    abort("no valid rows found");
}

close($infile);


my $insert = $db->prepare('insert into credentials (testip, port, context, technology, removed, passphrase) values (TO_BASE64(?), ?, ?, ?, ?, TO_BASE64(?))');

unless($noop) {
	foreach my $row (@rows) {
		$insert->execute(@$row);
	}

	print "1&Successfully imported $ip_count ips. Please refresh the page to update the table.\n";
	$insert->finish();
}

$db->disconnect();
exit(0);

## end execution
## subs -->

sub debug
{
	my $msg = shift;
	if ($debugging) {
		print STDERR $msg."\n";
	}
}

sub abort
{
	my $msg = shift;
	print STDOUT "0&$msg\n";
	exit(1);
}

sub logmsg
{
	my $msg = shift;
	$msg = "dbCredParser: $msg";
	my $now = localtime();
	my $ip;
	if ($ENV{'REMOTE_ADDR'}) {
		$ip = $ENV{'REMOTE_ADDR'};
	} else {
		$ip = undef;
	}
	eval {
		my $q = $db->prepare("insert into log (time,ip,action) values (?,?,?)");
		$q->execute($now,$ip,$msg);
	};
}
