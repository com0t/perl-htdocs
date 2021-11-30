#!/usr/bin/perl
#
## test access to a generic server via SSH

use strict;
use MIME::Base64;
use RISC::riscSSH;
use RISC::riscCreds;
use RISC::riscUtility;
use Data::Dumper;

## arguments take the following form, all within single quotes and base64-encoded, except for port:
#
## testGenSrvSSH.pl '<target> <username> <authtype> <authentication> <port> <priv>'
##   target:		IP of the target server
##   username:		duh
##   authtype:		either 'password' or 'publickey'
##   authentication:	either a password, or the path to a private key file
##   port:		duh, not base64-encoded
##   priv:		method of privilege escalation

my ($cred, $target);
my $cyberark_ssh = (-f "/etc/risc-feature/cyberark-ssh" && -f "/home/risc/conf/cyberark_config.json");

# use environment to avoid logging any sensitive strings - this is run via sudo
if (my $risc_credentials = riscUtility::risc_credentials("0&Failed to decode credentials\n")) {
	# limit what's passed to riscCreds to only what we're expecting
	$cred = { map {
		$_ => $risc_credentials->{$_}
	} qw(username context auth port priv keypass) };
	$target = $risc_credentials->{target};
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.+)\'$/;
	@ARGV = split(/\s/,$args);

	$target		= decode_base64(shift);
	$cred->{'username'}	= decode_base64(shift);
	$cred->{'context'}	= decode_base64(shift);
	$cred->{'auth'}		= $cyberark_ssh ? shift : decode_base64(shift);
	$cred->{'port'}		= shift;
	$cred->{'priv'}		= decode_base64(shift);
	$cred->{'keypass'}	= decode_base64(shift);	## if no passphrase, will be undef (even when decode_base64())
}

# $cred->{'auth'} above is a cyberark query string in this case.
if ($cyberark_ssh) {
	# calling docker exec requires root
	if ($< != 0) {
		print "0&cyberark enabled but running unprivileged\n";
		exit 1;
	}

	# complain if passed incorrect arguments
	if (!length($cred->{'auth'}) || $cred->{'auth'} eq 'null') {
		print "0&cyberark query string is empty\n";
		exit 1;
	}

	# rather than just die, run in eval { } to pass error back up to remote client
	my $credSet;
	eval {
		my $rc = riscCreds->new($target);
		$credSet = $rc->getGenSrvSSHCyberArkQueryString($cred->{'auth'});
	};
	# lots of ways to fail
	my $status;
	if ($@) {
		$status = $@;
	}
	elsif (!$credSet) {
		$status = 'no results';
	}
	elsif (exists($credSet->{'error'})) {
		$status = $credSet->{'error'};
	}
	if (length($status)) {
		print "0&cyberark query failed: $status\n";
		exit 1;
	}

	$cred->{'username'} = $credSet->{'username'};
	$cred->{'auth'} = $credSet->{'passphrase'};
}

## if debugging is on in either place, the frontend will break
my $ssh = RISC::riscSSH->new({ 'log_errors' => 0, 'debug' => 0, 'specify_skip_db' => 1 });

eval {
	$ssh->connect($target,$cred);
}; if (($@) or ($ssh->{'connected'} != 1)) {
	chomp(my $errmsg = $ssh->{'err'}->{'msg'});
	$errmsg =~ s/ at.*line.*$//g;
	print "0&$errmsg\n";
	exit 1;
}

## check for supported OS
unless ($ssh->supported_os()) {
	print "0&Unsupported Operating System: $ssh->{'os'}\n";
	exit 1;
}

# Validate privilege elevation. Due to an API change that was not handled very
# well, we need to call the correct method supported by the copy of
# `RISC::riscSSH` that is installed, which can differ depending on the RN150
# release version and whether or not initialization has occurred.
my $priv_method = 'privtest';
unless ($ssh->can($priv_method)) {
	$priv_method = 'test_sudo';
}

unless ($ssh->$priv_method()) {
	printf("0&Successfully connected, but privilege elevation using %s failed\n", $cred->{'priv'});
	exit 1;
}

my $sysdescr = $ssh->sysdescr();
if ($sysdescr) {
	print "1&$sysdescr\n";
	exit 0;
} else {
	print "0&Failed command 'uname -a'\n";
	exit 1;
}
