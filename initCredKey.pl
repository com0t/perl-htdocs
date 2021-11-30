#!/usr/bin/perl

# script to set random per-appliance cred/log encryption keys. it can be safely run on existing appliances any number of times.
# this adds a feature flag, 'init-cred-key', when run.
# if this script has already been run, supplying a single command line argument "--force", will force it to run again.

use Crypt::Random::Seed;
use Log::Log4perl;

use strict;
use warnings;

# from risc_discovery.sql
my $sql = q{
-- allow larger (128MiB) in-memory tables for the duration of this session. this is primarily for the 'log' table

SET max_heap_table_size = 134217728;

-- ensure decrypted temp tables don't wind up on disk

CREATE TEMPORARY TABLE log_backup ENGINE=MEMORY
SELECT id, time, ip, LOG_DECRYPT(action) from log;

CREATE TEMPORARY TABLE credentials_backup ENGINE=MEMORY
SELECT credid, productkey, technology, status, accepted, version, level, testip, CRED_DECRYPT(passphrase), CRED_DECRYPT(context), CRED_DECRYPT(securitylevel), CRED_DECRYPT(securityname), CRED_DECRYPT(authtype), CRED_DECRYPT(authpassphrase), CRED_DECRYPT(privtype), CRED_DECRYPT(privusername), CRED_DECRYPT(privpassphrase), CRED_DECRYPT(domain), port, CRED_DECRYPT(userid), CRED_DECRYPT(username), scantime, eu, ap, removed, credtag FROM credentials;

-- recreate credentials triggers/functions using new random key

DELIMITER //
DROP TRIGGER IF EXISTS risc_discovery.cred_encrypt//
CREATE TRIGGER cred_encrypt BEFORE INSERT ON credentials
FOR EACH ROW
BEGIN
	SET @key_str = UNHEX('%KEY_STR%');
	SET @init_vector = UNHEX('%INIT_VECTOR%');
	SET NEW.scantime = unix_timestamp(now());
	SET NEW.passphrase = AES_ENCRYPT(NEW.passphrase,@key_str,@init_vector);
	SET NEW.context = AES_ENCRYPT(NEW.context,@key_str,@init_vector);
	SET NEW.securitylevel = AES_ENCRYPT(NEW.securitylevel,@key_str,@init_vector);
	SET NEW.securityname = AES_ENCRYPT(NEW.securityname,@key_str,@init_vector);
	SET NEW.authtype = AES_ENCRYPT(NEW.authtype,@key_str,@init_vector);
	SET NEW.authpassphrase = AES_ENCRYPT(NEW.authpassphrase,@key_str,@init_vector);
	SET NEW.privtype = AES_ENCRYPT(NEW.privtype,@key_str,@init_vector);
	SET NEW.privusername = AES_ENCRYPT(NEW.privusername,@key_str,@init_vector);
	SET NEW.privpassphrase = AES_ENCRYPT(NEW.privpassphrase,@key_str,@init_vector);
	SET NEW.domain = AES_ENCRYPT(NEW.domain,@key_str,@init_vector);
	SET NEW.userid = AES_ENCRYPT(NEW.userid,@key_str,@init_vector);
	SET NEW.username = AES_ENCRYPT(NEW.username,@key_str,@init_vector);
	SELECT auto_increment INTO @initialseed FROM information_schema.tables
		WHERE table_name = 'credentials' AND table_schema = 'risc_discovery';
	SET NEW.credtag = concat(
		substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',rand(@seed:=round(rand(@initialseed)*4294967296))*36+1, 1),
		substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',rand(@seed:=round(rand(@seed)*4294967296))*36+1, 1),
		substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',rand(@seed:=round(rand(@seed)*4294967296))*36+1, 1)
	);
END;//

DROP TRIGGER IF EXISTS risc_discovery.cred_encrypt_update//
CREATE TRIGGER cred_encrypt_update BEFORE UPDATE ON credentials
FOR EACH ROW
BEGIN
	SET NEW.scantime = unix_timestamp(now());
	SET @key_str = UNHEX('%KEY_STR%');
	SET @init_vector = UNHEX('%INIT_VECTOR%');
	IF ((NEW.passphrase != OLD.passphrase) or (OLD.passphrase is NULL and NEW.passphrase is not NULL)) THEN
		SET NEW.passphrase = AES_ENCRYPT(NEW.passphrase,@key_str,@init_vector);
	END IF;
	IF ((NEW.context != OLD.context) or (OLD.context is NULL and NEW.context is not NULL)) THEN
		SET NEW.context = AES_ENCRYPT(NEW.context,@key_str,@init_vector);
	END IF;
	IF ((NEW.securitylevel != OLD.securitylevel) or (OLD.securitylevel is NULL and NEW.securitylevel is not NULL)) THEN
		SET NEW.securitylevel = AES_ENCRYPT(NEW.securitylevel,@key_str,@init_vector);
	END IF;
	IF ((NEW.securityname != OLD.securityname) or (OLD.securityname is NULL and NEW.securitylevel is not NULL)) THEN
		SET NEW.securityname = AES_ENCRYPT(NEW.securityname,@key_str,@init_vector);
	END IF;
	IF ((NEW.authtype != OLD.authtype) or (OLD.authtype is NULL and NEW.authtype is not NULL)) THEN
		SET NEW.authtype = AES_ENCRYPT(NEW.authtype,@key_str,@init_vector);
	END IF;
	IF ((NEW.authpassphrase != OLD.authpassphrase) or (OLD.authpassphrase is NULL and NEW.authpassphrase is not NULL)) THEN
		SET NEW.authpassphrase = AES_ENCRYPT(NEW.authpassphrase,@key_str,@init_vector);
	END IF;
	IF ((NEW.privtype != OLD.privtype) or (OLD.privtype is NULL and NEW.privtype is not NULL)) THEN
		SET NEW.privtype = AES_ENCRYPT(NEW.privtype,@key_str,@init_vector);
	END IF;
	IF ((NEW.privusername != OLD.privusername) or (OLD.privusername is NULL and NEW.privusername is not NULL)) THEN
		SET NEW.privusername = AES_ENCRYPT(NEW.privusername,@key_str,@init_vector);
	END IF;
	IF ((NEW.privpassphrase != OLD.privpassphrase) or (OLD.privpassphrase is NULL and NEW.privpassphrase is not NULL)) THEN
		SET NEW.privpassphrase = AES_ENCRYPT(NEW.privpassphrase,@key_str,@init_vector);
	END IF;
	IF ((NEW.domain != OLD.domain) or (OLD.domain is NULL and NEW.domain is not NULL)) THEN
		SET NEW.domain = AES_ENCRYPT(NEW.domain,@key_str,@init_vector);
	END IF;
	IF ((NEW.userid != OLD.userid) or (OLD.userid is NULL and NEW.userid is not NULL)) THEN
		SET NEW.userid = AES_ENCRYPT(NEW.userid,@key_str,@init_vector);
	END IF;
	IF ((NEW.username != OLD.username) or (OLD.username is NULL and NEW.username is not NULL)) THEN
		SET NEW.username = AES_ENCRYPT(NEW.username,@key_str,@init_vector);
	END IF;
END;//

DROP FUNCTION IF EXISTS cred_decrypt//
CREATE FUNCTION cred_decrypt(encrypted VARCHAR(255))
	RETURNS VARCHAR(255)
	LANGUAGE SQL
BEGIN
	return AES_DECRYPT(encrypted,UNHEX('%KEY_STR%'),UNHEX('%INIT_VECTOR%'));
END;//
DELIMITER ;

-- recreate log triggers/functions using new random key

DELIMITER //
DROP TRIGGER IF EXISTS risc_discovery.log_encrypt//
CREATE TRIGGER log_encrypt BEFORE INSERT ON log
FOR EACH ROW
BEGIN
	SET NEW.action = AES_ENCRYPT(NEW.action,UNHEX('%KEY_STR%'),UNHEX('%INIT_VECTOR%'));
END;//

DROP FUNCTION IF EXISTS log_decrypt//
CREATE FUNCTION log_decrypt(encrypted VARCHAR(255))
	RETURNS VARCHAR(255)
	LANGUAGE SQL
BEGIN
	return AES_DECRYPT(encrypted,UNHEX('%KEY_STR%'),UNHEX('%INIT_VECTOR%'));
END;//
DELIMITER ;

-- repopulate and reencrypt previous credentials/log rows using the new random key

TRUNCATE TABLE credentials;
INSERT INTO credentials SELECT * from credentials_backup;
DROP TEMPORARY TABLE credentials_backup;

TRUNCATE TABLE log;
INSERT INTO log SELECT * FROM log_backup;
DROP TEMPORARY TABLE log_backup;

-- add a row to features to signify that this has been run

REPLACE INTO features (name, val) VALUES('init-cred-key', 1);
};

my ($key_str_bytes, $init_vector_bytes) = (32, 16); # aes-256-cbc

my $log_conf = q{
	log4perl.rootLogger = INFO, SYSLOG
	log4perl.appender.SYSLOG = Log::Dispatch::Syslog
	log4perl.appender.SYSLOG.ident = risc-initCredKey
	log4perl.appender.SYSLOG.facility = user
	log4perl.appender.SYSLOG.layout = Log::Log4perl::Layout::PatternLayout
};

my $user = ((getpwuid($<))[0] eq 'www-data') ? 'risc-web' : 'risc';

Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();

$logger->info('begin');

# unless "--force" is passed as a command line parameter, ensure that the 'init-cred-key' feature flag hasn't yet been set before proceeding
unless (defined($ARGV[0]) && $ARGV[0] eq '--force') {
	chomp(my $count = `mysql risc_discovery -N -u $user -e "SELECT COUNT(*) FROM features WHERE name = 'init-cred-key' AND val = 1;" 2>&1`);

	($?)
		and $logger->error_die('failed to query features: ' . $count);

	($count eq '0')
		or $logger->error_die('found existing init-cred-key feature, run with argument "--force" to override');
}

my $entropy = Crypt::Random::Seed->new(); # gather bytes from /dev/random
my $key_str = unpack('H*', $entropy->random_bytes($key_str_bytes));
my $init_vector = unpack('H*', $entropy->random_bytes($init_vector_bytes));

(length($key_str) == ($key_str_bytes * 2) && length($init_vector) == ($init_vector_bytes * 2)) # hex
	or $logger->error_die('failed to collect entropy');

$sql =~ s/\Q%KEY_STR%\E/$key_str/g;
$sql =~ s/\Q%INIT_VECTOR%\E/$init_vector/g;

my $pid = open(my $mysql, '|mysql risc_discovery -u ' . $user)
	or $logger->error_die('failed to execute mysql: ' . $!);

print $mysql ($sql);

close($mysql);

($?)
	and $logger->error_die('mysql exited with ' . $?);

$logger->info('success');
