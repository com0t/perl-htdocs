#!/usr/bin/perl -w
use MIME::Base64;
use RISC::riscCreds;
use RISC::riscUtility;

my ($version, $target, $info, $cred);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials()) {
	$version = decode_base64($risc_credentials->{version});
	$target = decode_base64($risc_credentials->{target});

	if ($version == 3) {
		# limit what's passed to riscCreds to only what we're expecting
		$cred = { map {
			$_ => $risc_credentials->{$_}
		} qw(securitylevel securityname context authtype authpassphrase privtype privpassphrase) };
	} else {
		$cred = { map {
			$_ => $risc_credentials->{$_}
		} qw(passphrase) };
	}

	$cred->{version} = $version;
# the old fashioned way
} else {
	$version = decode_base64(shift);
	$target = decode_base64(shift);

	$cred->{'version'} = $version;

	if ($cred->{'version'} == 3) {
		$cred->{'securitylevel'} = shift;
		$cred->{'securityname'} = shift;
		$cred->{'context'} = shift;
		$cred->{'authtype'} = shift;
		$cred->{'authpassphrase'} = shift;
		$cred->{'privtype'} = shift;
		$cred->{'privpassphrase'} = shift;
	} else {
		$cred->{'passphrase'} = shift;
	}
}

my $obj = riscCreds->new();
my $res = $obj->testSNMP($cred,$target);
$obj->disconnect();

## this is what the PHP should expect
#print STDOUT join('&',$res->{'status'},$res->{'detail'})."\n";
## and this is what the PHP actually expects
if ($res->{'status'}) {
	print STDOUT "ReadOnly";
	exit(0);
} else {
	print STDOUT "NoAccess";
	exit(1);
}

