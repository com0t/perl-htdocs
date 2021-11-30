#!/usr/bin/perl

use Log::Log4perl; # skip dependencies on RISC stuff
use Symbol;
use IPC::Open3;
use IO::Select;
use Net::IP;
use File::Basename;
use FileHandle;
use Fcntl;
use JSON;

use strict;
use warnings;

use constant {
	OPENSSL => '/usr/bin/openssl',
	ALGORITHM => 'aes-256-cbc',
	DIGEST => 'sha256',
	CP => '/bin/cp',
	CHOWN => '/bin/chown',
	CHMOD => '/bin/chmod',
	SED => '/usr/bin/sed',
	USERADD => '/usr/sbin/useradd',
	SYSTEMCTL => '/bin/systemctl',
	APACHE_USER => 'www-data',
	MIGRATE_PSK => 'hMdFYRhgvqHefPmDYeYXeZdrMBeuogbCmZFGcqjuMDyBaAFKdKzyizcposYeXMhU', # ugh
	MIGRATE_USER => 'migration',
	MIGRATE_HOME => '/home/migration',
	MIGRATE_STATE_DIR => 'state',
	MIGRATE_STATE_FILE => 'configuration.json',
	MIGRATE_STAGING_DIR => 'staging',
	MIGRATE_SUDOERS_FILE => '/etc/sudoers.d/2_migration',
	MIGRATE_SUDOERS_CONF => "Defaults:migration !requiretty\nmigration ALL=NOPASSWD: /srv/httpd/htdocs/shell/migrate_data_postprocessing.pl \"\"\n",
	APPLIANCE_KEY => '/etc/riscappliancekey',
	SSH_OPTS => 'restrict,command="/srv/httpd/htdocs/shell/migrate_new_wrapper.sh",', # precise list of allowed commands is inside the referenced script
};

my $log_conf = q(
	log4perl.rootLogger = INFO, SYSLOG
	log4perl.appender.SYSLOG = Log::Dispatch::Syslog
	log4perl.appender.SYSLOG.ident = risc-migration
	log4perl.appender.SYSLOG.facility = user
	log4perl.appender.SYSLOG.layout = Log::Log4perl::Layout::PatternLayout
);

Log::Log4perl::init(\$log_conf);
my $logger = Log::Log4perl->get_logger();

$logger->info('begin ' . $0);

$SIG{__DIE__} = sub {
	$logger->error(shift) if ($logger);
};

(scalar(@ARGV) == 0)
	or $logger->error_die('invalid arguments');

# pass through the environment to avoid sudoers wildcards. env_keep will explicitly allow these two.
my ($migrate_new_ip, $migrate_new_encryption_key) = ($ENV{MIGRATE_NEW_IP}, $ENV{MIGRATE_NEW_ENCRYPTION_KEY});

$logger->info('validating encrypted key');
# just check if it's set and looks like base64 - openssl will determine if it's encrypted as expected, and further validation will be done on the decrypted key
length($migrate_new_encryption_key)
	or $logger->error_die('key not found in environment');

($migrate_new_encryption_key =~ /^[a-zA-Z0-9=\+\-\/\s]{64,}$/)
	or $logger->error_die('bad key format');

$logger->info('validating ip');
# more thorough validation of ip
length($migrate_new_ip)
	or $logger->error_die('ip not found in environment');

my $ip_obj = Net::IP->new($migrate_new_ip)
	or $logger->error_die('not an ip');

my $normalized = $ip_obj->ip();

($migrate_new_ip eq $normalized)
	or $logger->error_die('not an ip');

# add this to the environment and tell openssl to look there - slightly better than passing on cmdline
$ENV{PSK} = MIGRATE_PSK;

# openssl will expect the input to be base64 encoded, and encrypted with ALGORITHM (likely aes-256-cbc)
my ($result, $output, $error, $decrypted_key);

$logger->info('decrypting key');
($result, $decrypted_key, $error) = pipe_exec([OPENSSL, 'enc', '-' . ALGORITHM, '-d', '-base64', '-md', DIGEST, '-pass', 'env:PSK'], $migrate_new_encryption_key);
($result)
	and $logger->error_die('decrypt failed: ' . $error);

(scalar(split(/\v/, $decrypted_key)) == 1)
	or $logger->error_die('invalid key length');

$decrypted_key =~ s/\v//g;

# add the user, if it does not exist
if (!getpwnam(MIGRATE_USER)) {
	$logger->info('creating user');

	($result, $output, $error) = pipe_exec([USERADD, '-m', '-U', MIGRATE_USER]);
	($result)
		and $logger->error_die('failed to add migration user: '. $error);
}
else {
	$logger->info('user exists, skipping');
}

my $state_dir = MIGRATE_HOME . '/' . MIGRATE_STATE_DIR;
if (! -d $state_dir) {
	$logger->info('creating state dir');

	($result, $output, $error) = pipe_exec(['mkdir', $state_dir]);
	($result)
		and $logger->error_die('failed to create state dir: '. $error);
}
else {
	$logger->info('state dir exists, skipping');
}

my $staging_dir = MIGRATE_HOME . '/' . MIGRATE_STAGING_DIR;
if (! -d $staging_dir) {
	$logger->info('creating staging dir');

	($result, $output, $error) = pipe_exec(['mkdir', $staging_dir]);
	($result)
		and $logger->error_die('failed to create staging dir: '. $error);
}
else {
	$logger->info('staging dir exists, skipping');
}

# create the user ssh dir if it does not exist
my $user_ssh_dir = MIGRATE_HOME . '/.ssh';
if(! -d $user_ssh_dir) {
	$logger->info('creating .ssh dir');

	($result, $output, $error) = pipe_exec(['mkdir', $user_ssh_dir]);
	($result)
		and $logger->error_die('failed to create user ssh dir: '. $error);
}
else {
	$logger->info('.ssh dir exists, skipping');
}

$logger->info('setting permissions and ownership');
# keep things owned by root so it's not modifiable by the migration user
($result, $output, $error) = pipe_exec([CHOWN, 'root:' . APACHE_USER, $state_dir]);
($result)
	and $logger->error_die('failed to chown state dir: '. $error);

($result, $output, $error) = pipe_exec([CHMOD, '700', $staging_dir]);
($result)
	and $logger->error_die('failed to chmod staging dir: '. $error);

($result, $output, $error) = pipe_exec([CHMOD, '750', $state_dir]);
($result)
	and $logger->error_die('failed to chmod state dir: '. $error);

# set perms
($result, $output, $error) = pipe_exec([CHOWN, 'root:' . MIGRATE_USER, $user_ssh_dir]);
($result)
	and $logger->error_die('failed to chown user ssh dir: '. $error);

($result, $output, $error) = pipe_exec([CHOWN, '-R', MIGRATE_USER . ':' . MIGRATE_USER, $staging_dir]);
($result)
	and $logger->error_die('failed to chown staging dir: '. $error);

($result, $output, $error) = pipe_exec([CHMOD, '750', $user_ssh_dir]);
($result)
	and $logger->error_die('failed to chmod user ssh dir: '. $error);

# set umask before writing out key / state
my $old_umask = umask(oct('0026'));

$logger->info('copying appliance key');
# copy over psk so it's readable by the migration user
my $appliance_key = $staging_dir . '/' . basename(APPLIANCE_KEY);
($result, $output, $error) = pipe_exec([CP, '-a', APPLIANCE_KEY, $appliance_key]);
($result)
	and $logger->error_die('failed to copy appliance key: ' . $error);

($result, $output, $error) = pipe_exec([CHOWN, MIGRATE_USER . ':' . MIGRATE_USER, $appliance_key]);
($result)
	and $logger->error_die('failed to chown appliance key: ' . $error);

($result, $output, $error) = pipe_exec([CHMOD, '600', $appliance_key]);
($result)
	and $logger->error_die('failed to chmod appliance key: '. $error);

if (-e MIGRATE_SUDOERS_FILE) {
	$logger->info('unlinking existing sudoers file');

	unlink(MIGRATE_SUDOERS_FILE);
}

$logger->info('writing sudoers');
my $sudoers_fh = FileHandle->new;
$sudoers_fh->open(MIGRATE_SUDOERS_FILE, O_WRONLY|O_CREAT|O_EXCL)
	or $logger->error_die('failed to open sudoers file: ' . $!);

($result, $output, $error) = pipe_exec([CHMOD, '440', MIGRATE_SUDOERS_FILE]);
($result)
	and $logger->error_die('failed to chmod sudoers file: ' . $error);

$sudoers_fh->print(MIGRATE_SUDOERS_CONF)
	or $logger->error_die('failed to write sudoers file: ' . $!);

$sudoers_fh->close();

my $authorized_keys = $user_ssh_dir . '/authorized_keys';
if (-e $authorized_keys) {
	$logger->info('unlinking existing authorized_keys');

	unlink($authorized_keys);
}

$logger->info('writing out decrypted key');
my $ssh_fh = FileHandle->new;
# pass file mode to sysopen(), so we don't clobber anything
$ssh_fh->open($user_ssh_dir . '/authorized_keys', O_WRONLY|O_CREAT|O_EXCL)
	or $logger->error_die('failed to open ssh key file: '. $!);

# keep it owned by root so it's not modifiable by the user
($result, $output, $error) = pipe_exec([CHOWN, 'root:' . MIGRATE_USER, $authorized_keys]);
($result)
	and $logger->error_die('failed to chown authorized_keys: '. $error);

# finally, write out the key, only allowing a "single" command
$ssh_fh->print(SSH_OPTS . 'from="' . $migrate_new_ip . '" ' .  $decrypted_key . "\n")
	or $logger->error_die('failed to write ssh key: ' . $!);

$ssh_fh->close();

$logger->info('modifying ssh config');
# allow migration user to ssh in at the sshd level
($result, $output, $error) = pipe_exec([SED, '-E', '-i', 's/^AllowUsers admin$/AllowUsers admin migration/', '/etc/ssh/sshd_config']);
($result)
	and $logger->error_die('failed to modify ssh config: ' . $error);

$logger->info('starting sshd');
# finally, enable and start sshd
($result, $output, $error) = pipe_exec([SYSTEMCTL, 'unmask', 'ssh.service']);
($result, $output, $error) = pipe_exec([SYSTEMCTL, 'enable', 'ssh.service']);
($result, $output, $error) = pipe_exec([SYSTEMCTL, 'restart', 'ssh.service']); # restart to handle the case that it's already running (i.e. advanced debugging enabled)
($result)
	and $logger->error_die('failed to start ssh: '. $error);

# ... and write out the state so rn150-web can display settings for editing (likely, to change allowed ip)
$logger->info('writing state');
my $state_file = $state_dir . '/' . MIGRATE_STATE_FILE;
if (-e $state_file) {
	$logger->info('unlinking existing state file');

	unlink($state_file);
}

my $state_fh = FileHandle->new;
$state_fh->open($state_file, O_WRONLY|O_CREAT|O_EXCL)
	or $logger->error_die('failed to open state file: '. $!);

$state_fh->print(encode_json({ MIGRATE_NEW_IP => $migrate_new_ip, MIGRATE_NEW_ENCRYPTION_KEY => $migrate_new_encryption_key }) . "\n")
	or $logger->error_die('failed to write state file: ' . $!);

$state_fh->close();

($result, $output, $error) = pipe_exec([CHOWN, 'root:' . APACHE_USER, $state_file]);
($result)
	and $logger->error_die('failed to chown state file: '. $error);

umask($old_umask);

$logger->info('end ' . $0);

sub pipe_exec {
	my ($cmd, $input) = @_;

	my ($status, $stdout, $stderr);
	my ($child, $child_in, $child_out, $child_err);
	$child_err = gensym();
	my $io_select = IO::Select->new();

	eval {
		$child = open3(defined($input) ? $child_in : undef, $child_out, $child_err, @$cmd)
			or $logger->error_die($!);
	};
	if ($@) {
		$logger->error_die('exec failed: ' . $@);
		return;
	}

	$io_select->add($child_out, $child_err);

	if (defined($child_in)) {
		$child_in->print($input);
		$child_in->print("\n");
		$child_in->close();
	}

	my $rbuf = undef;
	my @ready_fh = ();
	while (@ready_fh = $io_select->can_read) {
		foreach my $fh (@ready_fh) {
			my $length = sysread($fh, $rbuf, 4096);
			if (!defined($length)) {
				$logger->error_die('error reading child fh: ' . $!);
			}
			elsif($length == 0) {
				$io_select->remove($fh);
			}
			else {
				if($fh == $child_out) {
					$stdout .= $rbuf;
				}
				else {
					$stderr .= $rbuf;
				}
			}
		}
	}

	waitpid($child, 0);
	$status = $?;

	return($status, $stdout, $stderr)
}
