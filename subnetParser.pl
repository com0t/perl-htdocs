#!/usr/bin/perl
#
## subnetcsv.pl
#
## validate, parse, and import subnets from csv

use strict;
use RISC::riscUtility;
use Time::HiRes;
use Data::Dumper;

# knobs
########
my $debugging	= 0;	## produce debugging output on STDERR
my $noop	= 0;	## just parse, don't insert anything

my $infilepath = shift;
unless ($infilepath) {
	abort("No file provided");
}
unless (-e $infilepath) {
	abort("No such file: $infilepath");
}

our $db = riscUtility::getDBH('risc_discovery',1);

## optional second argument overrides the noop knob
## if set and true, set noop --> 1
## if set and false (0), set noop --> 0
my $noop_arg = shift;
if (defined($noop_arg)) {
	if ($noop_arg) {
		$noop = 1;
	} else {
		$noop = 0;
	}
}

my $dos2unix = "dos2unix -q $infilepath";
my $dos2unixR = system($dos2unix);
unless ($dos2unixR == 0) {
	abort("Failed to convert line endings");
}

my $infile;
unless(open($infile,"<",$infilepath)) {
	abort("Could not open file");
}

my @subnets;
my $subnet_count = 0;
my $chars_read = 0;

my $starttime = Time::HiRes::time();

my $stop;
while (!defined($stop)) {
	my $subnet;
	my $count = 0;

	my $octet_count = 0;
	while ($octet_count < 4) {
		my $octet;
		my $octet_parse;
		$count = 0;
		my $octet_terminator;
		if ($octet_count == 3) {
			$octet_terminator = '/';
		} else {
			$octet_terminator = '.';
		}
		while ((!defined($octet_parse)) and ($count < 4) and (!eof($infile))) {
			my $char;
			if (eof($infile)) {
				logmsg("eof during octet parsing: '$octet' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
				parse_failure(($chars_read + 1),$subnet_count);
			}
			read($infile,$char,1);
			$chars_read++;
			$octet .= $char;
			if ($char eq $octet_terminator) {
				$octet_parse = 1;
			} elsif ($char eq "\n") {
				if ($count == 0) {
					$stop = 1;
					last;
				} else {
					logmsg("newline during octet parsing: '$octet' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
					parse_failure($chars_read,$subnet_count);
				}
			}
			$count++;
		}
		if ($stop) {
			last;
		}
		my $octet_pass;
		if ($octet_parse) {
			if ($octet =~ /^(\d{1,3})$octet_terminator$/) {
				if (($1 >= 0) and ($1 < 256)) {
					$octet_pass = 1;
				} else {
					logmsg("validation rejected: invalid octet value: '$1' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
					parse_failure($chars_read,$subnet_count);
				}
			} else {
				logmsg("validation rejected: '$octet' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
				parse_failure($chars_read,$subnet_count);
			}
		} else {
			logmsg("parser rejected: '$octet' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
			parse_failure($chars_read,$subnet_count);
		}
		if ($octet_parse and $octet_pass) {
			$subnet .= $octet;
		} else {
			logmsg("octet rejected: '$octet' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
			parse_failure($chars_read,$subnet_count);
		}
		$octet_count++;
	}
	if ($stop) {
		last;
	}

	$count = 0;
	my $slash;
	my $slash_parse;
	my $end_of_stream;
	while ((!defined($slash_parse)) and ($count < 3)) {
		my $char;
		if (eof($infile)) {
			$slash_parse = 1;
			$end_of_stream = 1;
			last;
		}
		read($infile,$char,1);
		$chars_read++;
		$slash .= $char;
		if (($char eq "\n") or ($char eq ',')) {
			$slash_parse = 1;
		}
		$count++;
	}
	my $slash_pass;
	if ($slash_parse) {
		if ($end_of_stream) {				## special handling for the last subnet in the stream
			if ($slash =~ /^\d{1,2}$/) {	## does not end with a newline or ','
				$slash_pass = 1;
			}
		} else {
			if ($slash =~ /^\d{1,2}(,|\n)/) {
				$slash_pass = 1;
			}
		}
	}
	if ($slash_parse and $slash_pass) {
		if ($slash =~ /(\n|,)$/) {
			chop($slash);
		}
		if ($slash < 16 || $slash > 32) {
			logmsg("subnet out of range: '$slash' char:$chars_read subnet:'$subnet' subnet#:".($subnet_count+1));
			mask_failure($chars_read,$subnet_count,$subnet,$slash);
		}

		$subnet .= $slash;
	} else {
		logmsg("mask rejected: '$slash' char:$chars_read subnet:'$subnet'");
		parse_failure($chars_read,$subnet_count);
	}

	if (eof($infile)) {
		$stop = 1;
	}

	if ($subnet =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}$/) {
		debug("===> $subnet");
		push(@subnets,$subnet);
		$subnet_count++;
	} else {
		logmsg("SUBNET REJECTED: '$subnet' char:$chars_read subnet#:".($subnet_count+1));
		parse_failure($chars_read,$subnet_count);
	}
}

my $totaltime = Time::HiRes::time() - $starttime;
debug("subnet_count: $subnet_count");
debug("chars_read:   $chars_read");
debug("parsed in:    $totaltime sec");

close($infile);

unless($noop) {
	my $insert = $db->prepare('insert into discoverystats (iprange,status) values (?,0)');
	foreach my $s (@subnets) {
		$insert->execute($s);
	}
	eval {
		$db->do("update configprog set validated = 1 where configstep = 'subnets'");
	};
	print "1&Successfully imported $subnet_count subnets\n";
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

sub parse_failure
{
	my $charnum = shift;
	my $subnetnum = shift;
	$subnetnum++;
	print STDOUT "0&Parsing failed on character $charnum, subnet $subnetnum: malformed data\n";
	exit(1);
}

sub mask_failure
{
	my ($charnum, $subnetnum, $subnet, $slash) = @_;

	$subnetnum++;
	print STDOUT "0&Parsing failed on subnet $subnetnum ($subnet$slash): subnet mask out of range, must be greater than or equal to /16 and less than or equal to /32\n";
	exit(1);
}


sub logmsg
{
	my $msg = shift;
	$msg = "subnetParser: $msg";
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
