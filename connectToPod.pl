#!/usr/bin/perl
use strict;
use RISC::riscConfigWeb;
use RISC::riscUtility;

my ($authuser, $authpass, $assesscode, $podip);

# use environment to avoid logging any sensitive strings - this is run via sudo
if (my $risc_credentials = riscUtility::risc_credentials("3&Failed to decode arguments\n")) {
	($authuser, $authpass, $assesscode, $podip) = map {
		$risc_credentials->{$_}
	} qw(authuser authpass assesscode podip);
# the old fashioned way
} else {
	my $args = shift;
	$args =~/^\'(.+)\'$/;
	@ARGV = split(/\s/, $args);

	$authuser = shift;
	$authpass = shift;
	$assesscode = shift;
	$podip = shift;
}

my $mysql = riscUtility::getDBH('risc_discovery',1);
#clear creds table
$mysql->do("delete from credentials where technology in ('cryptokey','flexpod')");

if ($podip =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/) {
        #we know we're dealing with an ip so we should have a flex pod there
        
        #clear out any flex keys on the keyring
        #we don't want to set up a potential infinite loop, but there may be multiples if something went wrong
        my $i = 0;
        while (`gpg --list-keys|grep flex` && $i < 100) {
                system('gpg --batch --yes --delete-keys flex@riscnetworks.com');
                $i++;
        }

        #now hit the pod api and get the podid
        # handle connection errors so the user gets a useful error message
        my $checkin = riscConfigWeb::podCheckIn($authuser,$authpass,$assesscode,$podip);

        unless (ref($checkin)) {
                print "3&Failed to check in: unable to communicate with FlexDeploy API";
                exit(1);
        }
        if ($checkin->{'returnStatus'} ne 'success') {
                print "3&Failed to check in: ".$checkin->{'returnStatusDetail'};
                exit(1);
        }
        my $podid = $checkin->{'podid'};

        #now add the pub cert to our keyring for encrypting the data uploads
        open my $pubkeyfile,'>','/home/risc/pubkey.gpg';
        my $pubkey = $checkin->{'pubkey'};
        print $pubkeyfile $pubkey;
        my $keyringCmd = "gpg --import /home/risc/pubkey.gpg &> /dev/null";
        system($keyringCmd);
        unless (`gpg --list-keys|grep flex`) {
                print "3&Failed to add key";
                exit(1);
        }

        #next call the headend to assign this assessment to the pod
        my $register = riscConfigWeb::registerToPod($authuser,$authpass,$assesscode,$podid);
        if ($register->{'returnStatus'} ne 'success') {
                print "3&Failed to register: ".$register->{'returnStatusDetail'};
                exit(1);
        }

        #now specify the flex cert in the credentials table
        
        $mysql->do("insert into credentials (technology,username)
                                        values(\'cryptokey\',\'flex\@riscnetworks.com\')");
        
        my $updatecreds = $mysql->prepare("insert into credentials (technology,testip)
                                        values(\'flexpod\', ?)");
        $updatecreds->execute($podip);

} else {
        #we are working with the headend -- check connectivity to the upload host?

        #set the pod id to indicate that we will rmove the host entry
        $podip = '0.0.0.0';
        
        $mysql->do("insert into credentials (technology,username)
                                        values(\'cryptokey\',\'jlittlejohn\@riscnetworks.com\')");
        $mysql->do("insert into credentials (technology,testip)
                                        values(\'flexpod\',\'none\')");
}

## update the hosts file record to point to where we want the uploads to go (pod, or headend)
eval {
        ## if we're using a pod, we need to add a record to point to the podip
        if ($podip ne '0.0.0.0') {
                my $hostRec = "$podip\tdataup.riscnetworks.com\n";
                $hostRec .= "127.0.0.1\tdataup1.riscnetworks.com\n";	## prevent the appliance from erroneously
                $hostRec .= "127.0.0.1\tdataup2.riscnetworks.com\n";	## uploading data to the NOC if onprem
                $hostRec .= "127.0.0.1\tdataup3.riscnetworks.com\n";
                $hostRec .= "127.0.0.1\tdataup4.riscnetworks.com\n";
                open my $hosts,'>>','/etc/hosts';
                print $hosts $hostRec;
                close $hosts;
                ## make sure this succeeded, as we don't want uploads to accidentally go to the headend
                unless (`cat /etc/hosts` =~ /$podip/) {
                        print '3&Error updating host record: podip entry addition failed';
                        exit(1);
                }
        }

        ## remove the existing record that points to localhost
        `grep -v 'removeme' /etc/hosts > /tmp/hosts.new && mv /tmp/hosts.new /etc/hosts`;
        ## make sure that didn't fail
        if (`cat /etc/hosts` =~ /removeme/) {
                print "3&Error updating host record: localhost entry not removed";
                exit(1);
        }

}; if ($@) {
        print "3&Error setting up host record: $@";
        exit(1);
}

#if we got here we didn't fail
print "1&Successfully registered to pod";
