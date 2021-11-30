#!/usr/bin/perl -w
use Data::Dumper;
use Switch;
#use Expect;
use DBI();
use lib 'lib';
use MIME::Base64;
$|++;

my $commandIP2=shift;
#$commandIP2=decode_base64($commandIP2);
#Initialize return value
$returnHash->{'status'}=0;
$returnHash->{'reason'}='generalFailure';
$returnHash->{'ip'}=undef;
#Now run all checks
#getCommandIP();
#my $commandIP2=$returnHash->{'ip'};
setupCrontab();
startArgus();
if ($commandIP2) {
      my $connection=connectMysql($commandIP2);
      if ($connection =~ /success/i) {
                setRN100Hostname($commandIP2);
            startNTP();
      }
}
print "$returnHash->{'status'}&$returnHash->{'reason'}\n";

#####################################################################################################

sub check_hostname {
        my $riscdiscovery=undef;
        open (MYFILE, '/etc/hosts');
        while (<MYFILE>) {
                if ($_=~/(^[\d]+\.[\d]+\.[\d]+\.[\d]+)\s+RISCDiscovery.*/){
                        $riscdiscovery=$1;
                }
        }
        #print "RISC Discovery Address is :$riscdiscovery\n";
        return $riscdiscovery;
}
sub checkNTPStatus {
        my $checkstring = "/usr/local/bin/ntpq -pn";
        my $pid = `$checkstring`;
        if (length($pid) >1) {
                my ($nothing,$remote,$refid,$st,$t,$when,$poll,$reach,$delay,$offset,$jitter)=split(/\s+/,$3);
                #print "Calculated offset is: ".$offset."\n";
                $pid=$offset;
               } else {
                        $pid = undef;
                }
        return $pid;
}
sub startNTP {
                                #replace ntp.conf with RN50 ntp.conf
                                system('rm /etc/ntp.conf');
                                system('echo server RISCDiscovery > /etc/ntp.conf');
                                #restart ntp
                                system('killall ntpd');
        my $datesetstring = "/usr/local/bin/ntpdate -b RISCDiscovery";
        my $startstring = "/usr/local/bin/ntpd";
        #print "Starting application...\n";
        my $startup = `$datesetstring`;
        #print "Result of NTPDate is: ".$startup."\n";
        my $startntp = `$startstring`;
        my $check = checkNTPStatus();
        #print "NTPOffset = $check\n";
        my $iterations = 1;
        while (defined $check) {
                return undef if $iterations==0;
                $iterations = $iterations -1;
                sleep 5;
                $check = checkNTPStatus();
        }
        my $pid = checkNTPStatus();
        if (defined $pid) {
                        return $pid;
                } else {
                        return undef;
                }
}
sub ping {
      my $dest=shift;
      my $pingresult=`/bin/ping -I eth3 -c 4 $dest`;
      my $result;
      if ($pingresult =~ /4 packets transmitted, (\d) received/i){
            $result=$1;
      } else {
            $result=$pingresult;
      }
      return $result;
}
sub traceroute {
      my $dest=shift;
      my $result=`/bin/traceroute $dest`;
      return $result;
}
sub getIpInfo {
      my $result = `/sbin/ifconfig`;
      $result.="\n\n\n".`/sbin/route`;
      return $result;
}
sub connectMysql {
      my $rn100 = shift;
      eval {
      my $mysql = DBI->connect(
                        "DBI:mysql:database=RISC_Discovery;host=$rn100;mysql_compression=1;mysql_connect_timeout=2",
                        "rn50","rn50secure",
                        {'RaiseError' =>1}
                        );
      }; if ($@) {$returnHash->{'status'}=0; $returnHash->{'reason'}="Unable to connect to RN150 at $rn100\n"; return undef;}
      $returnHash->{'status'}=1;
      $returnHash->{'reason'}="Connection to RN150 at $rn100 Successful\n";
      return "mysqlSuccess";
}

sub getCommandIP {
      eval {
            my $socket = '/run/mysqld/mysqld.sock';
            my $mysql = DBI->connect(
                        "DBI:mysql::database=risc_discovery:mysql_socket=$socket:host=localhost",
                        "risc","risc",
                        {'RaiseError' =>1}
                  );
        my $iplookup=$mysql->selectrow_hashref("select * from credentials where technology='rn150' and removed=0");
           
        if (not defined $iplookup->{'technology'}){
            $returnHash->{'status'}=0;
            $returnHash->{'reason'}='No IP Address Configured for RN150.  Please configure a valid IP Address in the RN150 Tab.';
            return undef;
        } elsif ($iplookup->{'technology'}) {
            my $commandip=decode_base64($iplookup->{'testip'});
            $returnHash->{'ip'}=$commandip;
            return undef;
        }      
    }; if ($@) {$returnHash->{'status'}=0; $returnHash->{'reason'}="Error connecting to database:$@"; return undef;}
}

sub setRN100Hostname {
      my $ip=shift;
      my @newfile;
      my $current=check_hostname();
      my $oldline = "127.0.0.1"."\t"."localhost\n"."";
      my $newline = $ip."\t"."RISCDiscovery\n";
      push(@newfile,$oldline);
      push(@newfile,$newline);
      
      #remove the HOSTS file here
      system("/usr/bin/rm /etc/hosts");
      #write the new HOSTS file here
      open HOSTS2,"+>",'/etc/hosts';
      foreach (@newfile) {
            printf HOSTS2 $_;
      }
      close HOSTS2;
}
sub checkProcess {
      my $process = shift;
      my @proclist = `pgrep -f $process`;
      my $result = @proclist;
      return $result;   
}

sub setupCrontab {
      my @newfile;

      my $newline = "*/1 * * * * root /usr/bin/perl /home/risc/rn50cc.pl\n";
      push(@newfile,$newline);
      my $newline2 = "*/5 * * * * root /usr/bin/perl /home/risc/argusLog.pl\n";
      push(@newfile,$newline2);
      open HOSTS2,">",'/etc/cron.d/rn50';
      foreach (@newfile) {
            printf HOSTS2 $_;
      }
      close HOSTS2;
      return;
}

sub startArgus {
	my @nics=(eth0,eth1,eth2,eth3,eth4,eth5);
	foreach $nic (@nics) {
		my $st = `/sbin/ifconfig $nic`;
		if ($st =~ /RX packets[:\s](\d+)/ ) {
			my $pkts=$1;
			if ($pkts > 0 && $st =~ /(eth.)/) {
				my $argusexec="/usr/sbin/argus -d -i $1 -w /home/risc/argus.out";
				system($argusexec);
			}
		}
	}
}

