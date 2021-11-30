#!/usr/bin/perl
#
##

## this script will enable/disable the proxy configuration system-wide

use strict;
use RISC::riscUtility;
use RISC::riscWebservice;
use MIME::Base64;
use URI::Escape qw/ uri_escape /;
use Data::Dumper;

my $args = shift;
$args =~/^\'(.+)\'$/;
@ARGV = split(/\s/, $args);

my $operation = shift;
my $proxyid = shift;

if ($operation eq 'enable') {
	unless (defined($proxyid)) {
		print "0&script error\n";
		exit(1);
	}
	enable_proxy($proxyid);
} elsif ($operation eq 'disable') {
	disable_proxy();
} else {
	print "0&script error\n";
	exit(1);
}


sub enable_proxy {
	my $proxyid = shift;

	my $db = riscUtility::getDBH('risc_discovery',1);
	my $config = $db->selectrow_hashref("select * from proxy where id = $proxyid and enabled = 1");

	unless ($config) {
		print "0&No such proxy configuration\n";
		exit(1);
	}

	my $proxycreds_file = '/root/proxycreds';

	$config->{'username'} = decode_base64($config->{'username'});
	$config->{'uri_username'} = uri_escape($config->{'username'});
	$config->{'password'} = decode_base64($config->{'password'});
	$config->{'uri_password'} = uri_escape($config->{'password'});

	if ($config->{'ntlm'}) {	## NTLM auth using cntlmd, assumes authenticate=1
		print "0&NTLM authenticating proxy currenty unsupported";
		exit(1);
	} else {
		my $httpproxy;		## standard for HTTP
		my $httpsproxy;		## standard for HTTPS
		my $HTTPPROXY;		## Perl SOAP for HTTP
		my $HTTPSPROXY;		## Perl SOAP for HTTPS
		my $HTTPSUSER;		## Perl SOAP for HTTPS username
		my $HTTPSPASS;		## Perl SOAP for HTTPS password
		my $proxycreds;		## proxytunnel directive to read username/password from file
		if ($config->{'authenticate'}) {
			# specifying https:// breaks things if the remote proxy isn't speaking native https back to us
			$httpsproxy = "http://$config->{'uri_username'}:$config->{'uri_password'}\@$config->{'address'}:$config->{'httpsport'}";
			$HTTPSPROXY = "http://$config->{'address'}:$config->{'httpsport'}";

			$httpproxy = "http://$config->{'uri_username'}:$config->{'uri_password'}\@$config->{'address'}:$config->{'httpport'}";
			$HTTPPROXY = "http://$config->{'address'}:$config->{'httpport'}";
			$HTTPSUSER = "$config->{'username'}";
			$HTTPSPASS = "$config->{'password'}";
			$proxycreds = "-F $proxycreds_file";	## tell proxytunnel to read auth creds from this file
		} else {
			# specifying https:// breaks things if the remote proxy isn't speaking native https back to us
			$httpsproxy = "http://$config->{'address'}:$config->{'httpsport'}";

			$httpproxy = "http://$config->{'address'}:$config->{'httpport'}";
			$HTTPPROXY = $httpproxy;
			$HTTPSPROXY = $httpsproxy;
			$HTTPSUSER = "";
			$HTTPSPASS = "";
			$proxycreds = "";	## expands to nothing in the proxytunnel command, effectively disabling authentication
		}

		## Write /etc/riscenvironment, sourced by /etc/profile
		my $fh;

		if ($config->{'authenticate'}) {
			system('install -o root -g root -m 600 /dev/null ' . $proxycreds_file);
			open($fh, '>', $proxycreds_file);
			print $fh "proxy_user=$config->{'username'}\n";
			print $fh "proxy_passwd=$config->{'password'}\n";
			close($fh);
		}

		## Write /etc/environment, used by cron
		open($fh,">>","/etc/environment");
		print $fh "http_proxy=\"$httpproxy\"\n";
		print $fh "https_proxy=\"$httpsproxy\"\n";
		# LWP gets confused and randomly picks either HTTP(s)_PROXY or http(s)_proxy depending on the weather
		# however, it doesn't pull in the _USERNAME and _PASSWORD when it does this. so just set one of the two
		print $fh "PERL_LWP_ENV_PROXY=\"1\"\n";
		print $fh "no_proxy=\"localhost,127.0.0.1,::1\"\n";

		close($fh);

		## set up the advanced debugging elements
		if (! -d "/root/.ssh") {
			system("mkdir /root/.ssh");
			system("chown root:root /root/.ssh");
			system("chmod 750 /root/.ssh");
		}
		open($fh,">","/root/.ssh/config.proxy");
		my $proxytunnel = '/usr/bin/proxytunnel';
		my $cfg = <<EOM;
StrictHostKeyChecking no
Host *.riscnetworks.com
	DynamicForward 1080
	ProxyCommand $proxytunnel -v -p $config->{'address'}:$config->{'httpsport'} $proxycreds -r app1.riscnetworks.com:443 -d \%h:22 -H \"User-Agent: Mozilla/4.0 (compatible; MSIE 6.0; Win32)\\n\" -X
	ServerAliveInterval 30
EOM
		print $fh $cfg;
		close($fh);
	}

	## disable apt ssl verification for https://initial.riscnetworks.com (note: gpg signing is still used)
	if (open(my $aptconf, '>', '/etc/apt/apt.conf.d/50risc-proxy')) {
		print $aptconf ('Acquire::https::initial.riscnetworks.com::Verify-Peer "false";' . "\n");
		print $aptconf ('Acquire::https::initial.riscnetworks.com::Verify-Host "false";' . "\n");

		close($aptconf);
	}

	print "1&Successfully enabled proxy configuration";

	## send a notification that proxy has been utilized, if the proxy-notify feature is enabled
	riscWebservice::sendAlarm(
			encode_base64($0),
			1,
			encode_base64('proxy utilized'),
			encode_base64('a proxy configuration has been applied'),
			encode_base64('notify')
		) if (riscUtility::checkfeature('proxy-notify'));
}

sub disable_proxy {
	my $fh;

	## remove entries from /etc/environment
	my @env;
	open($fh,"<","/etc/environment");
	while (my $line = <$fh>) {
		if ($line !~ /(http(s|)_proxy|^no_proxy|^PERL_LWP_ENV_PROXY)/i) {
			push(@env,$line);
		}
	}
	close($fh);
	open($fh,">","/etc/environment");
	foreach my $line (@env) {
		print $fh $line;
	}
	close($fh);
	## remove the /srv/httpd/htdocs/proxy-config.php file (legacy, no longer used)
	if (-e "/srv/httpd/htdocs/proxy-config.php") {
		unlink("/srv/httpd/htdocs/proxy-config.php");
	}
	## remove the advanced debugging bits
	if (-e "/root/.ssh/config.proxy") {
		unlink("/root/.ssh/config.proxy");
	}
	if (-e "/root/proxycreds") {
		unlink("/root/proxycreds");
	}
	## remove apt ssl verification override
	if (-e "/etc/apt/apt.conf.d/50risc-proxy") {
		unlink("/etc/apt/apt.conf.d/50risc-proxy");
	}

	print "1&Successfully removed proxy configuration";
}
