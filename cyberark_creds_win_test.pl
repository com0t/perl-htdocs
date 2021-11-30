#!/usr/bin/perl
#
## get creds from CyberArk to be used in testing creds for Windows

use strict;
use warnings;
use MIME::Base64;
use RISC::riscCreds;
use RISC::riscWindows;
use RISC::riscUtility;

## perl cyberark_creds_win_test.pl '<target> <CyberArk query string>'
## or
##  RISC_CREDENTIALS='{"target":"1.2.3.4","queryString":"someCyberArkQuery"}' perl cyberark_creds_win_test.pl
##
##   target:            IP of the target server
##   CyberArk query string:             duh

my ($target, $queryString);

# use environment to avoid logging any sensitive strings - this is run via sudo
if (my $risc_credentials = riscUtility::risc_credentials()) {
	($target, $queryString) = map {
		$risc_credentials->{$_}
	} qw(target queryString);
# the old fashioned way
} else {
	my $args = shift;
	$args =~ /^\'(.+)\'$/;
	@ARGV = split(/\s/,$args);

	$target = decode_base64(shift);
	$queryString = shift;
}

my $credobj = riscCreds->new($target);
my $credSet = $credobj->getWinCyberArkQueryString($queryString);

# prepWin inserts the domain if present into the username
$credSet = riscCreds->prepWin($credSet);

my $user = $credSet->{'user'};
my $pass = $credSet->{'password'};

if (length($user) and length($pass)) {
    my $win = RISC::riscWindows->new({user => $user, password => $pass, host => $target});
    if ($win->connected() != 1) {
        print($win->err());
    } else {
        print($win->connected());
    }
} else {
    print("Error retrieving credentials from CyberArk: " . $credobj->get_error())
}
