#!/usr/bin/perl -w
use strict;
use DBI;
use MIME::Base64;
use RISC::riscUtility;
use RISC::riscCreds;
use Time::Local;
use POSIX;

# I don't really know what the structure this plugs into looks like;
# I am basing this script off of testWindows.pl, input-and-output-wise.

## pass: '<dbtype> <user> <password> <ip> <port> <sid-if-oracle>'
# where <dbtype> must be one of: mysql mssql oracle
# it would be possible to resolve a hostname into an ip ourselves but it's probably safer to let them do it

## returns:
#		0&DBIerror
#		1&success
#		2&privilegeWarning
#
# the final option will return when a suspiciously small number of schemas and/or connections are returned
# by the probe, implying that, although technically we were able to access the database just fine, we suspect
# that maybe we don't have the right permissions. This should probably give the user a yellow-light notification
# and encourage them to verify that the account has the needed permissions (which depend on dbtype) to proceed.

my $cyberark_db = (-f "/etc/risc-feature/cyberark-ssh" && -f "/home/risc/conf/cyberark_config.json");

my ($dbtype, $username, $pw, $serverip, $cport, $orsid);

# use environment to avoid logging any sensitive strings - this is run via sudo
if (my $risc_credentials = riscUtility::risc_credentials(sub { abort_test('Failed to decode arguments') })) {
	($dbtype, $username, $pw, $serverip, $cport, $orsid) = map {
		$risc_credentials->{$_}
	} qw(dbtype username pw serverip cport orsid);
# the old fashioned way
} else {
	# copied from testWindows, with an audible quantity of side-eye:
	my $args = shift;
	$args =~/^\'(.+)\'$/;
	@ARGV = split(/\s/, $args);

	# are the inputs passed in in base64? if not then this is going to make a hot mess.
	$dbtype = decode_base64(shift);
	$username = decode_base64(shift);
	$pw = $cyberark_db ? shift : decode_base64(shift);
	$serverip = decode_base64(shift);
	$cport = decode_base64(shift);
	$orsid = decode_base64(shift) if ($dbtype eq "oracle");
}

# $pw above is a cyberark query string in this case. username and orsid are unused, other fields are as-is
if ($cyberark_db) {
	# calling docker exec requires root
	if ($< != 0) {
		abort_test('cyberark enabled but running unprivileged');
	}

	# complain if passed incorrect arguments
	if (!length($pw) || $pw eq 'null') {
		abort_test('cyberark query string is empty');
	}

	# rather than just die, run in eval { } to pass error back up to remote client
	my $cred;
	eval {
		my $rc = riscCreds->new();
		$cred = $rc->getDBCyberArkQueryString($pw, $dbtype);
	};
	# lots of ways to fail
	my $status;
	if ($@) {
		$status = $@;
	}
	elsif (!$cred) {
		$status = 'no results';
	}
	elsif (exists($cred->{'error'})) {
		$status = $cred->{'error'};
	}
	
	abort_test('cyberark query failed: ' . $status) if (length($status));

	($username, $pw, $orsid) = map { $cred->{$_} } qw(username passphrase securityname);
}

my $returnCode;
my $returnDetail;
my $accessible = 1;
my $initialNumSchemas = 0;
my $initialNumConns = 0;
my $initialNumTables = 0;
my $initialNumAnalyzed = 0;

if ($dbtype eq "mysql") {
	my $dbstr = ("DBI\:mysql\:\:host=$serverip;port=$cport");
	
	my $dbh;
	($dbh,$accessible) = connect_with_timeout($dbstr, $username, $pw);
	if (!$accessible) {
		abort_test(sprintf('Connection failed: %s: %s', $DBI::err, $DBI::errstr));
	} else {
		my $schemasquery = $dbh->prepare("SELECT SCHEMA_NAME FROM information_schema.schemata");
		if ($DBI::err) {
			abort_test(sprintf('Unable to list schemata: %s', $DBI::errstr));
		}
		$schemasquery->execute();
		while ($schemasquery->fetchrow_hashref){
			$initialNumSchemas++;
		}
		my $connquery = $dbh->prepare("SELECT host, db, command, state, time FROM information_schema.processlist");
		if ($DBI::err) {
			abort_test(sprintf('Unable to query processlist: %s', $DBI::errstr));
		}
		$connquery->execute();
		while ($connquery->fetchrow_hashref){
			$initialNumConns++;
		}

	}
} elsif ($dbtype eq "mssql"){
	# we must deal with the fcking config file
	my $configname = "$serverip\:$cport";
	my $conffile = '/etc/freetds/freetds.conf';
        my $appears = 0;
        open(my $fh, "<", $conffile) or die("failed opening tds config file\n");
        while(my $line=$fh->getline()){
                if($line=~$configname){
                        $appears = 1;
                        last;
                }
        } # end search config
        close($fh);
        if(!$appears){
                open($fh, '>>', $conffile);
                say $fh '['.$configname .']';
                say $fh "\thost = $serverip";
                say $fh "\tport = $cport";
                say $fh "\ttds version = 7.1";
		say $fh "\tuse ntlmv2 = yes";
		say $fh "\tencryption = request";
                say $fh '';
                close($fh);
        } # end write to config file

	my $dbstr = 'DBI:Sybase:server=' . $configname;
	my $dbh;
	($dbh,$accessible) = connect_with_timeout($dbstr, $username, $pw);
	if (!$accessible){
		abort_test(sprintf('Connection failed: %s: %s', $DBI::err, $DBI::errstr));
	}else{
		my $verQ = $dbh->selectrow_hashref("select CAST(SERVERPROPERTY ('ProductVersion') AS VARCHAR) v");
		my ($verN) = $verQ->{'v'} =~ /^(\d*)./;
		if ($verN < 10){
			$accessible = 0;
			$returnCode = 0;
			$returnDetail = "Invalid MS SQL Server version: $verN";
		}

		my $schemasquery = $dbh->prepare("SELECT name, database_id, create_date FROM sys.databases");
		if ($DBI::err) {
			abort_test(sprintf('Unable to query sys.databases: %s', $DBI::errstr));
		}
		$schemasquery->execute();
		my @schemarray;
		while (my $sch = $schemasquery->fetchrow_hashref){
			$initialNumSchemas++;
			push @schemarray, $sch->{'name'};
		}

		my $msbigq = 'SELECT conn.client_net_address, '.
			'conn.client_tcp_port, '.
			'sess.status, '.
			'sess.last_request_start_time, '.
			'DB_NAME(sess.database_id) AS db ' .
			'FROM sys.dm_exec_sessions sess '.
			'LEFT JOIN sys.dm_exec_connections conn '.
			'ON sess.session_id=conn.session_id '.
			'WHERE sess.is_user_process=1;';
		$msbigq = 'SELECT conn.client_net_address, conn.client_tcp_port, sess.status, sess.last_request_start_time,
				dat.name as db from sys.dm_exec_sessions sess inner join sys.dm_exec_connections conn
				on sess.session_id = conn.session_id
				inner join master.dbo.sysprocesses pro on sess.session_id = pro.spid
				inner join sys.databases dat on pro.dbid = dat.database_id
				where sess.is_user_process=1' if $verN==10;
		my $connquery = $dbh->prepare($msbigq);
		if ($DBI::err) {
			abort_test(sprintf('Unable to query connections: %s', $DBI::errstr));
		}
		$connquery->execute();
		while ($connquery->fetchrow_hashref){
			$initialNumConns++;
		}
	}
} elsif ($dbtype eq "oracle"){
	eval{system('sudo /srv/httpd/htdocs/shell/hosts_update.sh');};	## sudo, as we're running this as 'apache'
	my $dbstr = "dbi:Oracle:host=$serverip;port=$cport;sid=$orsid";
	my $dbh;
	($dbh,$accessible) = connect_with_timeout($dbstr, $username, $pw);
	if (!$accessible){
		abort_test(sprintf('Connection failed: %s: %s', $DBI::err, $DBI::errstr));
	}else{
		my $schemasquery = $dbh->prepare("SELECT username FROM dba_users u WHERE EXISTS (SELECT 1 FROM dba_objects o WHERE o.owner = u.username)");
		if ($DBI::err) {
			abort_test(sprintf('Unable to query users: %s', $DBI::errstr));
		}
		$schemasquery->execute();
		while ($schemasquery->fetchrow_hashref){
			$initialNumSchemas++;
		}
		my $orbigq = "SELECT MACHINE, PORT, SCHEMANAME, STATUS, COMMAND, LAST_CALL_ET FROM v\$session WHERE username IS NOT NULL";
		my $connquery = $dbh->prepare($orbigq);
		if ($DBI::err) {
			abort_test(sprintf('Unable to inspect v$session, this Oracle version is not supported: %s', $DBI::errstr));
		}
		$connquery->execute();
		while ($connquery->fetchrow_hashref){
			$initialNumConns++;
		}
		my $rowsq = "select
			table_name, owner, sum(decode(type,'table',bytes))/1024 tableKB,
			sum(decode(type,'index',bytes))/1024 indexKB, sum(decode(type,'lob',bytes))/1024 lobKB,
			sum(bytes)/1024 totalKB, sum(num_rows) numRows, max(last_anal) last_anal,
			max(created) created, max(updated) updated, max(tbs) tablespace,
			sum(decode(type,'table',bytes,'lob',bytes))/1024 totalDataKB,
			sum(decode(type,'index',bytes,'lobidx',bytes))/1024 totalIdxKB
		from (
			select t.table_name table_name, 'table' type, t.owner, s.bytes, t.num_rows,
				t.last_analyzed last_anal, o.created created, o.last_ddl_time updated, t.tablespace_name tbs
			from dba_tables t left join dba_segments s
				on s.segment_name=t.table_name and s.owner=t.owner
				left join dba_objects o on t.table_name=o.object_name and t.owner=o.owner
			where s.segment_type in ('TABLE','TABLE PARTITION','TABLE SUBPARTITION') or s.segment_type is null
			union all select i.table_name table_name, 'index' type, i.owner, s.bytes, 0 num_rows,
				null last_anal, null created, null updated, null tbs
			from dba_segments s inner join dba_indexes i
				on i.index_name = s.segment_name and s.owner = i.owner
			where s.segment_type in ('INDEX','INDEX PARTITION','INDEX SUBPARTITION')
			union all select l.table_name, 'lob' type, l.owner, s.bytes, 0 num_rows, null last_anal,
				null created, null updated, null tbs
			from dba_lobs l inner join dba_segments s on l.segment_name = s.segment_name and l.owner = s.owner
			where s.segment_type in ('LOBSEGMENT','LOB PARTITION')
			union all select l.table_name, 'lobidx' type, l.owner, s.bytes, 0 num_rows, null last_anal,
				null created, null updated, null tbs
			from dba_lobs l inner join dba_segments s on l.index_name = s.segment_name and s.owner = l.owner
			where s.segment_type = 'LOBINDEX' )
		group by table_name, owner";

	}
}

if($accessible && $initialNumSchemas<2){
	$returnCode=2;
	$returnDetail = "Suspiciously small number of schemas; recommend check permissions for the supplied account.";
}elsif($accessible && $initialNumConns<2){
	$returnCode=2;
	$returnDetail = "Suspiciously small number of connections found; recommend check permissions for the supplied account.";

}elsif($accessible){
	$returnCode=1;
	$returnDetail = "Success";
}



print $returnCode . "&" . $returnDetail;
print "\n";

##################################SUBS###############################################################

sub conffilewrite{
	my $conffile = '/etc/freetds/freetds.conf';
	my $configname = shift; #"$serverip\:$cport";
	my $appears = 0;
	open(my $fh, "<", $conffile) or die("failed opening tds config file\n");
	while(my $line=$fh->getline()){
		if($line=~$configname){
			$appears = 1;
			last;
		}
	} # end search config
	close($fh);
	if(!$appears){
		open($fh, '>>', $conffile);
		say $fh '['.$configname .']';
		say $fh "\thost = $serverip";
		say $fh "\tport = $cport";
		say $fh "\ttds version = 7.0";
		say $fh '';
		close($fh);
	} # end write to config file
	# okay, christ, that's done with.
}

sub oraToUnixDate{
	return if !defined($_[0]);
	# this takes the oracle date string, and makes it into a unix time. the time of day is set to be 00:00:00
	my ($day, $mon, $yr) = split('-',shift);
	my $mon_num = 0;
	my @mon_arr = ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC");
	# ^ slightly inefficient as I'm defining this array each time the function is called.
	++$mon_num until $mon_arr[$mon_num] eq $mon;
	my $udate = timegm(0, 0, 0, $day, $mon_num, $yr);
	return $udate;
}

sub abort_test {
	my ($message) = @_;
	chomp($message);
	printf("%s\n", join('&', 0, $message));
	exit(1);
}

sub connect_with_timeout {
        my $db_str = shift;
        my $user_name = shift;
        my $p_w = shift;

        my $dbh;
        my $accessible = 1;

        my $mask = POSIX::SigSet->new( SIGALRM );
        my $action = POSIX::SigAction->new(
                sub { die "connect timeout\n" },
                $mask,
        );
        my $oldaction = POSIX::SigAction->new();
        my $failed;
        sigaction( SIGALRM, $action, $oldaction);
        eval {
                eval {
                        alarm(70); # longer than internal DBI timeout but not too long, I hope?
                        $dbh = DBI->connect($db_str, $user_name, $p_w,{LongTruncOk => 1,PrintError=>0,RaiseError=>0})
                                or $accessible = 0;
                        1;
                } or $failed=1;
                alarm(0);
                die "$@\n" if $failed;
                1;
        } or $failed = 1;
        sigaction( SIGALRM, $oldaction );
        if ( $failed ) {
                $accessible = 0;
                abort_test('connection attempt hung');
        }
        return $dbh, $accessible;
}
