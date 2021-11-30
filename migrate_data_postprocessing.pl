#!/usr/bin/perl
use strict;
use warnings;

use File::Slurp;
use RISC::Collect::Logger;

my $logger = RISC::Collect::Logger->new('migration_data_postprocessing');
my $migration_staging_path = '/home/migration/staging';
my $original_network_conf_path = "$migration_staging_path/original_network_conf";

unless (-e "$migration_staging_path/mysql" && -e "$migration_staging_path/freetds.conf") {
	$logger->error_die("Missing required files for migration. Please check data transfer processes on original appliance");
}
if (-e "$original_network_conf_path/proxy.sql" || -e "$original_network_conf_path/ports.sql") {
	$logger->error_die("proxy.sql/ports.sql network configs already exist in ${original_network_conf_path}.");
} elsif (-e "$migration_staging_path/mysql_original") {
	$logger->error_die("$migration_staging_path/mysql_original already exists.");
} elsif (-e "$migration_staging_path/freetds.conf_original") {
	$logger->error_die("$migration_staging_path/freetds.conf_original already exists.");
}

# Back up the existing proxy, ports, and ntp tables from the new rn150
my $cmd = "mkdir -p $original_network_conf_path &&
	mysqldump risc_discovery proxy > $original_network_conf_path/proxy.sql 2>$original_network_conf_path/proxy.stderr";
if(!system($cmd)) {
	$logger->info('Successfully backed up proxy table');
} else {
	chomp(my $err = read_file("$original_network_conf_path/proxy.stderr"));
	$logger->error_die("Failed to back up proxy table: $err");
}

$cmd = "mysqldump risc_discovery ports > $original_network_conf_path/ports.sql 2>$original_network_conf_path/ports.stderr";
if(!system($cmd)) {
	$logger->info('Successfully backed up ports table');
} else {
	chomp(my $err = read_file("$original_network_conf_path/ports.stderr"));
	$logger->error_die("Failed to back up ports table: $err");
}

$cmd = "mysqldump risc_discovery ntp > $original_network_conf_path/ntp.sql 2>$original_network_conf_path/ntp.stderr";
if(!system($cmd)) {
	$logger->info('Successfully backed up ntp table');
} else {
	chomp(my $err = read_file("$original_network_conf_path/ntp.stderr"));
	$logger->error_die("Failed to back up ntp table: $err");
}

# Die handler to rollback changes if there is an error
$SIG{__DIE__} = sub {
	# the __DIE__ handler is executed even when die() is called in any number of nested eval blocks
	# so we don't prematurely roll back the mysql dir etc., make sure it's actually fatal before acting
	if ($^S) {
		return;
	}

	$logger->error("fatal exception: $@");

	if (-d "$migration_staging_path/mysql_original") {
		# Replace the contents of /var/lib/mysql with the original data
		service_mysql('stop');
		my $cmd = "mv /var/lib/mysql $migration_staging_path/mysql &&
			mv $migration_staging_path/mysql_original /var/lib/mysql && chown -R mysql:mysql /var/lib/mysql/";
		system($cmd);
		service_mysql('start');
	} if (-e "$migration_staging_path/freetds.conf_original") {
		# Replace freetds.conf file with the original
		my $cmd = "cp $migration_staging_path/freetds.conf_original /etc/freetds/freetds.conf &&
			chown root:www-data /etc/freetds/freetds.conf && chmod 660 /etc/freetds/freetds.conf";
		system($cmd);
	}
};

# Stop mysql service
service_mysql('stop');

# Replace the contents of /var/lib/mysql with the new data
$cmd = "mv /var/lib/mysql $migration_staging_path/mysql_original && mv $migration_staging_path/mysql /var/lib/mysql && chown -R mysql:mysql /var/lib/mysql/";
if(!system($cmd)) {
	$logger->info('Successfully replaced mysql data');
} else {
	$logger->error_die('Failed to replace mysql data');
}

# Start mysql service
service_mysql('start');

# Run mysql_upgrade
$cmd = "mysql_upgrade 2>&1";
if(!system($cmd)) {
	$logger->info('Successfully ran mysql_upgrade');
} else {
	$logger->error_die('Failed to run mysql_upgrade');
}

# Install auth_socket plugin in mysql
$cmd = "mysql -e \"INSTALL PLUGIN auth_socket SONAME \'auth_socket.so\';\"";
if(!system($cmd)) {
	$logger->info('Successfully installed auth_socket mysql plugin');
} else {
	$logger->error_die('Failed to install auth_socket mysql plugin');
}

# Restart mysql service
service_mysql('restart');

# Alter users to use auth_socket and drop rn50 user
$cmd = q{
	mysql -e "
	ALTER USER IF EXISTS
	  root@localhost IDENTIFIED WITH auth_socket,
	  root@127.0.0.1 IDENTIFIED WITH auth_socket,
	  root@'::1' IDENTIFIED WITH auth_socket,
	  risc@localhost IDENTIFIED WITH auth_socket AS 'root';
	DROP USER IF EXISTS rn50;
	CREATE USER IF NOT EXISTS 'risc-web'@'localhost' IDENTIFIED WITH auth_socket AS 'www-data';
	GRANT ALL ON risc_discovery.* to 'risc-web'@'localhost';
	GRANT ALL ON RISC_Discovery.* to 'risc-web'@'localhost';
	FLUSH PRIVILEGES;"
};

if(!system($cmd)) {
	$logger->info('Successfully altered users to use auth_socket');
} else {
	$logger->error_die('Failed to alter users to use auth_socket');
}

# Disable AWS collection, as it's unsupported on Debian-based appliances
$cmd = q{mysql risc_discovery -e "DELETE FROM features WHERE name = 'cloud-aws';"};
if(!system($cmd)) {
	$logger->info('Successfully disabled unsupported cloud-aws feature');
} else {
	$logger->error_die('Failed to disable unsupported cloud-aws feature');
}

# Reload the ports and proxy tables
$cmd = "mysql --skip-comments risc_discovery < $original_network_conf_path/proxy.sql 2>&1 && mysql --skip-comments risc_discovery < $original_network_conf_path/ports.sql 2>&1 && mysql --skip-comments risc_discovery < $original_network_conf_path/ntp.sql 2>&1";
if(!system($cmd)) {
	$logger->info('Successfully loaded original proxy, ports, and ntp tables');
} else {
	$logger->error_die('Failed to load original proxy, ports, and ntp tables');
}

# Add keys to /home/risc/keys
$cmd = "rsync -ra $migration_staging_path/keys /home/risc &&
	chown -R root:root /home/risc/keys &&
	chmod -R 400 /home/risc/keys &&
	chown root:www-data /home/risc/keys &&
	chmod 770 /home/risc/keys";
if(!system($cmd)) {
	$logger->info('Successfully added keys to /home/risc/keys');
} else {
	$logger->error_die('Failed to add keys to /home/risc/keys');
}

# Add datafiles to /home/risc/datafiles (for FDP)
$cmd = "rsync -ra $migration_staging_path/datafiles /home/risc &&
	chown -R root:root /home/risc/datafiles &&
	chmod -R 644 /home/risc/datafiles && 
	chmod 755 /home/risc/datafiles";

if(!system($cmd)) {
	$logger->info('Successfully added datafiles to /home/risc/datafiles');
} else {
	$logger->error_die('Failed to add datafiles to /home/risc/datafiles');
}

# Replace freetds.conf file
$cmd = "cp /etc/freetds/freetds.conf $migration_staging_path/freetds.conf_original &&
	cp $migration_staging_path/freetds.conf /etc/freetds/freetds.conf &&
	chown root:www-data /etc/freetds/freetds.conf && chmod 660 /etc/freetds/freetds.conf";

if(!system($cmd)) {
	$logger->info('Successfully replaced freetds.conf file');
} else {
	$logger->error_die('Failed to replace freetds.conf to file');
}

# Import pubkey.gpg if it is supplied (for FDP)
$cmd = "cp $migration_staging_path/fdp_migration_data/pubkey.gpg /home/risc/ &&
	chown root:root /home/risc/pubkey.gpg && chmod 600 /home/risc/pubkey.gpg &&
	gpg --import $migration_staging_path/fdp_migration_data/pubkey.gpg";

if(!-e "$migration_staging_path/fdp_migration_data/pubkey.gpg") {
	$logger->info('No pubkey.gpg file to import');
} elsif(!system($cmd)) {
	$logger->info('Successfully imported pubkey.gpg');
} else {
	$logger->error_die('Failed to import pubkey.gpg');
}

# Add entries to /etc/hosts if supplied (for FDP)
$cmd = "cat $migration_staging_path/fdp_migration_data/host_dataup_redirect >> /etc/hosts";

if(!-e "$migration_staging_path/fdp_migration_data/host_dataup_redirect") {
	$logger->info('No /etc/hosts entries to add');
} elsif(!system($cmd)) {
	$logger->info('Successfully added entries to /etc/hosts');
} else {
	$logger->error_die('Failed to add entries to /etc/hosts');
}

sub service_mysql {
	my $action = shift;
	my $cmd = "service mysql $action";
	if(!system($cmd)) {
		$logger->info("Successfully ${action}ed mysql");
	} else {
		$logger->error_die("Failed to $action mysql");
	}
}
