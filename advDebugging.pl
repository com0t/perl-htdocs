#!/usr/bin/perl
#
## advDebugging.pl: enable/disable remote advanced debugging, and report status

use strict;
use RISC::riscUtility;

my $proxytunnel = '/usr/local/bin/proxytunnel';

my $enable_mode = '755';
my $disable_mode = '644';

my $is_unavail = "0&Advanced Debugging is disabled and cannot be enabled at this time\n";
my $is_enabled = "1&Advanced Debugging is enabled\n";
my $is_disabled = "2&Advanced Debugging is disabled\n";
my $script_error = "3&An error has occurred. If the problem persists, please contact us through the community: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape\n";

my $directive = shift;
unless($directive) {
	$directive = 'disable';
}

my $db = riscUtility::getDBH('risc_discovery',0);
unless($db) {
	print $script_error;
	exit(1);
}

if ($directive eq 'status') {
	my $dbstatus = get_status();
	unless (defined($dbstatus)) {
		print $script_error;
		exit(1);
	}
	if ($dbstatus == 1) {
		print $is_enabled;
		exit(0);
	} else {
		print $is_disabled;
		exit(0);
	}
} elsif ($directive eq 'enable') {
	set_enabled();
	print $is_enabled;
} elsif ($directive eq 'disable') {
	set_disabled();
	print $is_disabled;
} else {
	print $script_error;
	exit(1);
}

sub get_status
{
	my $stat;
	eval {
		$stat = $db->selectrow_hashref("select val from features where name = 'rssh'")->{'val'};
	};
	return $stat;
}

sub set_disabled
{
	system('systemctl stop ssh.service');
	system('systemctl mask ssh.service');

	$db->do("update features set val = 0 where name = 'rssh'");
	kill_active();
}

sub set_enabled
{
	system('systemctl unmask ssh.service');
	system('systemctl enable ssh.service');
	system('systemctl start ssh.service');

	$db->do("update features set val = 1 where name = 'rssh'");
}

sub kill_active
{
	system("pkill -f machine1.riscnetworks.com &> /dev/null");
	system("pkill -f proxytunnel &> /dev/null");
}

