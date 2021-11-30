#!/usr/bin/perl
#
## returns output indicating whether our connection to orchestration is proxied or not
## will also detect whether said connection was successful or not
#
## output format:
##    <proxystatus>&<connectionstatus>
##    proxystatus: 0 = not proxied, 1 = proxied
##    connectionstatus: 0 = unsuccessful, 1 = successful
##    eg:
##    0&1  indicates that we successfully connected and are not proxied
##    1&1  indicates that we successfully connected through a proxy
##    1&0  indicates that we failed to connect through a proxy

use strict;
use IPC::Open3;
use IO::Select;

## get the ip addresses currently mapped to orchestration.riscnetworks.com
my @orchips;
my $orch_ip_res = system_plus("host orchestration.riscnetworks.com");
my @orch_ip_res = split(/\n/,$orch_ip_res->{'stdout'});
foreach my $line (@orch_ip_res) {
	my ($ip) = $line =~ /.*address (.*)$/;
	push(@orchips,$ip);
}

## get the ip address of the endpoint when we wget orchestration.riscnetworks.com
my $wget_ip;
my $wget_res = system_plus("wget -O /dev/null --no-check-certificate https://orchestration.riscnetworks.com/");
my @wget_res = split(/\n/,$wget_res->{'stdout'});
foreach my $line (@wget_res) {
	if ($line =~ /Connecting to/) {
		if ($line =~ /\|/) {
			($wget_ip) = $line =~ /Connecting to orchestration\.riscnetworks\.com\|(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\|.*/;
		} else {
			($wget_ip) = $line =~ /Connecting to (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/;
		}
		last;
	}
}

## store whether we connected or not
my $connected = 0;
$connected = 1 if ($wget_res->{'returncode'} == 0);

## loop through the orchestration IPs, if our connection IP matches one of these then we are not proxied
## if no matches, then we are proxied
my $proxy = 1;
foreach my $orch (@orchips) {
	if ($wget_ip == $orch) {
		$proxy = 0;
		last;
	}
}

## print the status and exit
print "$proxy&$connected";
exit(0);


sub system_plus {
        my($cmd) = @_; 
        my $return;
        my $pid = open3(my $in, my $out, my $err, $cmd);
        my $sel = new IO::Select;
        $sel->add($out, $err);
        while(my @fhs = $sel->can_read) {
                foreach my $fh (@fhs) {
                        my $line = <$fh>;
                        unless(defined $line) {
                                $sel->remove($fh);
                                next;
                        }
                        if($fh == $out) {
                                $return->{'stdout'} .= $line;
                        }elsif($fh == $err) {
                                $return->{'error'} .= $line;
                        }else{
                                die "[ERROR]: This should never execute!";
                        }
                }
        }
        waitpid($pid, 0); 
        $return->{'returncode'} = $? >> 8;
        return $return;
}
