#!/usr/bin/perl
#
##
use strict;
use MIME::Base64;
use RISC::riscCreds;
use RISC::riscUtility;

## pass: '<serverip> <port> <username> <password>'

## shell escaped arguments
my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

## probably a no-op, as we need to call riscUtility::loadenv() to get the proxy configuration, which we have not
## we protect against proxying the VMware connection anyway, in case this above behavior changes
riscUtility::proxy_disable();

my $cred;
my $customport;

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials('0&Failed to decode credentials')) {
	# limit what's passed to riscCreds to only what we're expecting
	$cred = { map {
		$_ => $risc_credentials->{$_}
	} qw(domain port username passphrase) };

	$customport = $cred->{port};
# the old fashioned way
} else {
	$cred->{'domain'} = shift; ## server IP
	$customport = shift; ## port that was passed
	$cred->{'username'} = shift;
	$cred->{'passphrase'} = shift;
}

$cred->{'port'} = encode_base64('443'); ## it was decided to statically use this until we find an instance where it's not

my $credobj = riscCreds->new();
my $res = $credobj->testVMware($cred,$cred->{'domain'});
print STDOUT join('&',$res->{'status'},$res->{'detail'});
