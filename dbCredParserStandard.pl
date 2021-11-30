#!/usr/bin/perl
#
## validate, parse, and import DB creds from csv

use strict;
use warnings;
use RISC::riscUtility;
use Net::IP;
use Text::CSV;

# knobs
########
my $noop	= 0;	## just parse, don't insert anything

# take in file path
my $infilepath = shift;
my $noop_arg = shift;
my	$removed = 0;

unless ($infilepath) {
    abort("No file provided");
}
unless (-e $infilepath) {
    abort("No such file: $infilepath");
}

# initialize Text::CSV
my $csv = Text::CSV->new({sep_char => ',', allow_whitespace => 1});

my $db = riscUtility::getDBH('risc_discovery',1);

## optional second argument overrides the noop knob
## if set and true, set noop --> 1
## if set and false (0), set noop --> 0

if (defined($noop_arg)) {
    if ($noop_arg) {
        $noop = 1;
    } 
}

my $infile;
unless(open($infile,"<",$infilepath)) {
    abort("Could not open file");
}

my @rows_add;
my @rows_remove;
my $ip_count_add = 0;
my $ip_count_remove = 0;
my $valid_dbtypes = {'mysql' => 1, 'mssql' => 1, 'oracle' => 1};
my $valid_actions = {'add' => 1, '1' => 1, 'remove' => 0, '0' => 0};

# standard csv input format:

while (my $row = $csv->getline($infile)) {
    my ($action, $ip, $username, $password, $dbtype, $port, $sid) = @$row;
    next unless defined($ip); # empty lines / trailing newline can be skipped over
    my $lc_dbtype = lc $dbtype;

    if (!defined($valid_actions->{$action})) {
        my $error = 'invalid action: ' . $action;
        logmsg($error);
        abort($error);
    }

    # IP Validation Steps
    my $ip_obj = Net::IP->new($ip);
    if (!$ip_obj) {
        my $error = 'not an ip: ' . Net::IP::Error();
        logmsg($error);
        abort($error);
    }
    my $normalized = $ip_obj->ip();
    if ($ip ne $normalized) {
        my $error = 'not an ip: ' . $ip;
        logmsg($error);
        abort($error);
    }
    if (!length($port) || $port !~ /^\d+$/ || $port < 1 || $port > 65535) {
        my $error = 'invalid port: ' . $port;
        logmsg($error);
        abort($error);
    }
    if (!$valid_dbtypes->{$lc_dbtype}) {
        my $error = 'invalid db type: ' . $dbtype;
        logmsg($error);
        abort($error);
    }
    if ($lc_dbtype eq 'oracle' && !defined($sid)) {
        my $error = 'missing Oracle SID';
        logmsg($error);
        abort($error);
    }
    
    if ($valid_actions->{$action}) {
        push(@rows_add, [$lc_dbtype, $ip, $port, $username, $password, $sid]);
        $ip_count_add++;
    } else {
        push(@rows_remove, [$lc_dbtype, $ip, $port, $username, $password, $sid]);
        $ip_count_remove++;
    }
}

$csv->eof or do {
    my $error = 'csv parsing failed: ' . $csv->error_diag();
    logmsg($error);
    abort($error);
};

if ($ip_count_add + $ip_count_remove == 0) {
    abort("no valid rows found");
}

close($infile);


my $insert = $db->prepare("insert into credentials (technology, context, testip, port, username, passphrase, securityname)
    values ('db', ?, TO_BASE64(?), ?, TO_BASE64(?), TO_BASE64(?), TO_BASE64(IFNULL(?,'')))");

my $remove = $db->prepare("update credentials set removed = 1 where technology = 'db'
    and cred_decrypt(context) = ? and testip = TO_BASE64(?) and port = ? and cred_decrypt(username) = TO_BASE64(?) 
    and cred_decrypt(passphrase) = TO_BASE64(?) and if(cred_decrypt(context) = 'oracle', cred_decrypt(securityname) = TO_BASE64(?), true)");

my $actually_removed = 0;

unless($noop) {
    foreach my $row (@rows_add) {
        $insert->execute(@$row);
    }

    foreach my $row (@rows_remove) {
        my $affected = $remove->execute(@$row);
        $actually_removed++ if $affected > 0; # don't count multiple rows if any
    }

    print "1&Successfully imported $ip_count_add databases and matched/removed $actually_removed of $ip_count_remove records. Untested credentials will be validated during discovery.\n";
    $insert->finish();
}

$db->disconnect();
exit(0);

## end execution
## subs -->

sub abort
{
    my $msg = shift;
    print STDOUT "0&$msg\n";
    exit(1);
}

sub logmsg
{
    my $msg = shift;
    $msg = "dbCredParser: $msg";
    my $now = time();
    my $ip;
    if ($ENV{'REMOTE_ADDR'}) {
        $ip = $ENV{'REMOTE_ADDR'};
    } else {
        $ip = undef;
    }
    eval {
        my $q = $db->prepare("insert into log (time,ip,action) values (FROM_UNIXTIME(?),?,?)");
        $q->execute($now,$ip,$msg);
    };
}
