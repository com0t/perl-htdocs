#!/usr/bin/perl

use RISC::riscUtility;

use Log::Log4perl;
use File::Slurp;

use strict;
use warnings;

use constant {
	DEFAULT_SERVER => 'ntp.riscnetworks.com', # if the customer sets the server as this, regardless of pool/server etc., it will use DEFAULT_CONFIG below
	DEFAULT_CONFIG => 'pool ntp.riscnetworks.com key 1 iburst version 4',
	DEFAULT_KEY => '1 SHA512 HEX:8EB1FDFCB7571268D4DDD00CCBD3A2776078CC1189681933846015F8FDFE43AF74630E0EDF4DE4DFAC28D9D6193D6D67FB03FFE5DFF3433C8D7661502382CC57',
	CONFIG_DIR => '/etc/chrony/chrony.d',
	CONFIG_DIR_PERMS => 0755,
	CONFIG_DIR_OWNER => 'root:root',
	CONFIG_FILE => 'risc.conf',
	CONFIG_FILE_PERMS => 0644,
	CONFIG_FILE_OWNER => 'root:root',
	KEY_PATH => '/etc/chrony/chrony.keys',
	KEY_PERMS => 0600,
	KEY_OWNER => 'root:root',
};

my $log_conf = q(
	log4perl.rootLogger = INFO, SYSLOG
	log4perl.appender.SYSLOG = Log::Dispatch::Syslog
	log4perl.appender.SYSLOG.ident = risc-ntp
	log4perl.appender.SYSLOG.facility = user
	log4perl.appender.SYSLOG.layout = Log::Log4perl::Layout::PatternLayout
);

Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();

$logger->info('begin with args: ' . join(' ', @ARGV));

my ($operation, $id) = @ARGV;

(defined($operation))
	or $logger->error_die('operation not set');

if ($operation eq 'disable') {
	disableNtp()
		or $logger->error_die('unable to disable ntp: ' . $@);
}
elsif ($operation eq 'enable') {
	(defined($id) && $id =~ /^\d+$/)
		or $logger->error_die('invalid id');

	my $config = getConfig($id)
		or $logger->error_die('unable to fetch config: ' . $@);

	enableNtp($config)
		or $logger->error_die('unable to enable ntp: ' . $@);
}
else {
	$logger->error_die('invalid operation');
}

$logger->info('success');

print('Successfully ' . $operation . 'd NTP', "\n");

exit(0);

sub disableNtp {
	my @disable_cmds = (
		# stop and disable chrony
		'systemctl stop chrony.service',
		'systemctl disable chrony.service',
		'systemctl mask chrony.service',

		# enable and run 'vmware-toolbox-cmd timesync enable'
		'systemctl enable vmware-timesync.service',
		'systemctl restart vmware-timesync.service',
	);

	$logger->info('disableNtp()');

	runCmds(@disable_cmds)
		or return(undef);

	return(1);
}

sub enableNtp {
	my $config = shift;

	my @enable_cmds = (
		# disable vmware timesync
		'systemctl disable vmware-timesync.service',
		'vmware-toolbox-cmd timesync disable',

		# enable and (re)start chrony
		'systemctl unmask chrony.service',
		'systemctl enable chrony.service',
		'systemctl restart chrony.service',
	);

	$logger->info('enableNtp(' . dumpHash($config) . ')');

	writeConfig($config)
		or return(undef);

	runCmds(@enable_cmds)
		or return(undef);

	return(1);
}

sub runCmds {
	my @cmds = @_;

	$logger->info('runCmds(...)');

	foreach my $cmd (@cmds) {
		my $output = qx($cmd 2>&1);
		($?) and do {
			$@ = 'non-zero return status from "' . $cmd . '": ' . $?;
			$logger->error("runCmds(...): $@");
			$logger->error("runCmds(...): output was: $output");
			return(undef);
		};
	}

	return(1);
}

sub writeConfig {
	my $config = shift;

	my $chrony_conf;

	$logger->info('writeConfig(' . dumpHash($config) . ')');

	if ($config->{address} eq DEFAULT_SERVER) {
		# ignore whether we're told to be a pool or server
		$chrony_conf = DEFAULT_CONFIG . "\n";

		# write out auth key, as ntp.riscnetworks.com can utilize this
		write_file(KEY_PATH, { err_mode => 'quiet' }, DEFAULT_KEY . "\n") or do {
			$@ = 'write key: ' . $!;
			return(undef);
		};

		applyPerms(KEY_PATH, KEY_OWNER, KEY_PERMS) or do {
			$@ = 'key permissions: ' . $@;
			return(undef);
		};
	}
	else {
		$chrony_conf = join(' ', $config->{type}, $config->{address}, "iburst\n");
	}

	if (! -d CONFIG_DIR) {
		mkdir(CONFIG_DIR) or do {
			$@ = 'create config directory: ' . $!;
			return(undef);
		};
	}

	applyPerms(CONFIG_DIR, CONFIG_DIR_OWNER, CONFIG_DIR_PERMS) or do {
		$@ = 'config directory permissions: ' . $@;
		return(undef);
	};

	my $config_path = CONFIG_DIR . '/' . CONFIG_FILE;
	write_file($config_path, { err_mode => 'quiet' }, $chrony_conf) or do {
		$@ = 'write config file: ' . $!;
		return(undef);
	};

	applyPerms($config_path, CONFIG_FILE_OWNER, CONFIG_FILE_PERMS) or do {
		$@ = 'config file permissions: ' . $@;
		return(undef);
	};

	return(1);
}

sub getConfig {
	my $id = shift;

	my $config;

	$logger->info("getConfig($id)");

	eval {
		my $dbh = riscUtility::getDBH('risc_discovery', 1);
		$config = $dbh->selectrow_hashref('SELECT address, type, enabled FROM ntp WHERE id = ' . $id);
		$dbh->disconnect();
	};
	if ($@) {
		$@ = 'query failed: ' . $@;
	}
	elsif (!defined($config)) {
		$@ = 'no rows match id ' . $id;
	}
	elsif ($config->{address} !~ /^[a-zA-Z0-9\-\.]+$/) {
		$@ = 'invalid address "' . $config->{address} . '"';
	}
	elsif ($config->{type} !~ /^(server|pool)$/) {
		$@ = 'invalid type "' . $config->{type} . '"';
	}
	elsif ($config->{enabled} != 1) {
		$@ = 'id ' . $id . ' is not enabled';
	}

	return(undef) if ($@);

	return($config);
}

sub applyPerms {
	my ($path, $owner, $perms) = @_;

	$logger->info("applyPerms($path, $owner, $perms)");

	my ($user, $group) = split(/:/, $owner);

	chmod($perms, $path) or do {
		$@ = 'chmod failed: ' . $!;
		return(undef);
	};

	chown((getpwnam($user))[2], (getgrnam($group))[3], $path) or do {
		$@ = 'chown failed: ' . $!;
		return(undef);
	};

	return(1);
}

sub dumpHash {
	my $hash = shift;

	my $scalar = join(', ',
		map {
			$_ . ' => ' . $hash->{$_}
		} sort(keys %$hash)
	);

	return("{ $scalar }");
}
