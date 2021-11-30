#!/usr/bin/perl

# simple network utility
# - ping (hostname or ip)
# - nslookup (hostname or ip)
# - traceroute (hostname or ip)
# - http (proto + hostname or ip + port)
# - tcp_connect (hostname or ip + port)
#
# output is JSON

use JSON;
use IO::Socket::INET;
use IO::Handle;
use IO::Select;
use IPC::Open3;
use POSIX qw(:sys_wait_h);
use Time::HiRes qw(gettimeofday tv_interval sleep);
use LWP::UserAgent;
#use Data::Dumper;

use RISC::riscUtility;

use strict;
use warnings;

use constant {
	SUCCESS => 1,
	FAILURE => 0,
};

my $script_timeout = 300; # script will abort regardless after this many seconds

my $commands = {
	ping => \&do_ping,
	nslookup => \&do_nslookup,
	traceroute => \&do_traceroute,
	http => \&do_http,
	tcp_connect => \&do_tcp_connect,
};

my $validators = {
	ping => \&validate_host,
	nslookup => \&validate_host,
	traceroute => \&validate_host,
	http => \&validate_url,
	tcp_connect => \&validate_host_port,
};

my ($mode, $target) = @ARGV;

(defined($mode) && length($mode) && defined($target) && length($target))
	or response(FAILURE, "Missing parameters", "Mode and/or target is unset.");

(scalar(@ARGV) == 2)
	or response(FAILURE, "Invalid arguments", "Only two arguments permitted: <mode> <target>");

(defined($validators->{$mode}) && defined($commands->{$mode}))
	or response(FAILURE, "Bad mode", "Mode '$mode' is unknown.");

$SIG{ALRM} = sub { response(FAILURE, "script timeout", "Maximum runtime of $script_timeout seconds reached, aborting."); };
alarm($script_timeout);

$commands->{$mode}->( $validators->{$mode}->($target) );

sub response {
	my ($status, $message, $output) = @_;

	print encode_json({
		status => $status,
		message => $message,
		output => $output,
	});

	exit(0);
}

sub validate_host {
	my $host = shift;

	# far cry from restricting to only valid ipv4 / hostnames, but enough to filter most garbage
	if (defined($host) && length($host) && length($host) <= 255 && $host =~ /^[a-z0-9]+[\.\-a-z0-9]*[a-z0-9\.]$/i) {
		return({host => $host});
	}

	response(FAILURE, "Bad host", "Host '$host' is invalid.\n\nPlease use a hostname or IPv4 address like: www.example.org or 192.0.2.1.");
}

sub validate_port {
	my $port = shift;

	if (defined($port) && ($port =~ /^\d+$/) && ($port > 0) && ($port <= 65535)) {
		return({port => $port});
	}

	response(FAILURE, "Bad port", "Port '$port' is invalid.\n\nPlease use a port number between 1-65535.");
}

sub validate_host_port {
	my $host_port = shift;

	if ($host_port =~ /^(?<host>.+):(?<port>\d+)$/) {
		validate_host($+{host});
		validate_port($+{port});

		return({host => $+{host}, port => $+{port}});
	}

	response(FAILURE, "Bad target", "Target '$host_port' is invalid.\n\nPlease format the host and port like: www.example.org:80 or 192.0.2.0:22.");
}

sub validate_url {
	my $url = shift;

	# note that this intentionally disallows arguments, such as /index.html /somepage.php?foo=bar, for security reasons
	if ($url =~ /^(?:(?<protocol>https?)(?::\/\/))?(?<host>[0-9a-zA-Z\-\.]+)(?::(?<port>\d+))?\/?$/) {
		my $protocol = defined($+{protocol}) ? $+{protocol} : 'http';
		my $host = $+{host};
		my $port = defined($+{port}) ? $+{port} : ($protocol eq 'http' ? 80 : 443);

		validate_host($host);
		validate_port($port);

		return({protocol => $protocol, host => $host, port => $port});
	}

	response(FAILURE, "Bad URL", "URL '$url' is invalid.\n\nPlease format the URL like: https://www.example.org, http://example.org:80/, or www.example.org.");
}

sub do_ping {
	my $t = shift;

	my $host = $t->{host};

	pipe_exec(['ping', '-c4', '-4', $host], 15);
}

sub do_nslookup {
	my $t = shift;

	my $host = $t->{host};

	pipe_exec(['nslookup', $host], 10);
}

sub do_traceroute {
	my $t = shift;

	my $host = $t->{host};

	pipe_exec(['traceroute', '-4', $host], 60);
}

sub do_http {
	my $t = shift;

	my ($protocol, $host, $port) = ($t->{protocol}, $t->{host}, $t->{port});
	my ($timeout, $max_len) = (15, 1024);

	# parse and load /etc/environment - needed for proxy
	riscUtility::loadenv();

	my $ua = LWP::UserAgent->new(
		max_size => $max_len, # in case the '/' points to a 10GB file
		protocols_allowed => ['http', 'https'],
		requests_redirectable => [], # don't automatically follow redirects
		timeout => $timeout,
		env_proxy => 1,
		ssl_opts => {
			verify_hostname => !exists($ENV{https_proxy}),
			SSL_verify_mode => !exists($ENV{https_proxy}),
		},
	);

	my $response = $ua->get($protocol . '://' . $host . ':' . $port);

	riscUtility::proxy_disable();

	response($response->is_success ? SUCCESS : FAILURE, $response->status_line, $response->as_string);
}

sub do_tcp_connect {
	my $t = shift;

	my ($host, $port) = ($t->{host}, $t->{port});
	my ($timeout, $max_len) = (5, 1024);
	my $output = '';

	my $tcp = IO::Socket::INET->new(
		PeerAddr => $host,
		PeerPort => $port,
		Proto => 'tcp',
		Timeout => $timeout,
		Blocking => 0,
	) or response(FAILURE, "Connection failure", "Unable to connect to $host:$port: " . ($@ ? ($@ =~ s/^IO::Socket::INET: //r) : $!));

	my $start = [gettimeofday];

	my $select = IO::Select->new($tcp);

	my ($bytes, $recvbuf) = (0, '');
	while (tv_interval($start) < $timeout) {
		$! = 0;
		if (!$select->can_read(0.5)) {
			if ($!) {
				response(FAILURE, "Read error", "Error encountered when reading from $host:$port: $!");
			}

			next;
		}

		my $read_len = $tcp->sysread($recvbuf, $max_len);

		if (!$read_len) {
			# eof or error
			last;
		}

		$bytes += $read_len;

		$output .= $recvbuf;

		# enough to get an ssh banner, e.g. "SSH-2.0-OpenSSH_8.4\r\n"
		if ($output =~ /^(?<line>.*?)\r?\n/) {
			$output = $+{line};
			last;
		}

		# otherwise, capture up to $max_len bytes
		if ($bytes >= $max_len) {
			last;
		}
	}

	$select->remove($tcp);

	$tcp->close();

	# truncate the string to $max_len bytes
	$output = substr($output, 0, $max_len);

	response(SUCCESS, "Success", $output);
}

sub pipe_exec {
	my ($command, $timeout) = @_;

	$timeout = 30 if (!defined($timeout));
	my $max_len = 8192; # should be plenty for any of ping / traceroute / nslookup

	my ($pid, $child, $output);

	eval {
		$child = IO::Handle->new();
		# stderr intentionally missing - we want both streams combined
		$pid = open3(undef, $child, undef, @$command)
			or die($!);
	};
	if ($@) {
		response(FAILURE, "Command failed", "Failed to execute '" . join(' ', @$command) . "': $@");
	}

	my $start = [gettimeofday];

	my $select = IO::Select->new($child);

	my ($bytes, $rbuf, $timed_out) = (0, '', 1);
	while (tv_interval($start) < $timeout) {
		$! = 0;
		if (!$select->can_read(0.5)) {
			if ($!) {
				response(FAILURE, "Select failed", "Failed to poll subprocess output: $!");
			}

			next;
		}

		my $read_len = $child->sysread($rbuf, $max_len);

		if (!defined($read_len)) {
			response(FAILURE, "Read failed", "Failed to read subprocess output: $!");
		}
		elsif (!$read_len) {
			# eof
			$timed_out = 0;
			last;
		}
		else {
			$output .= $rbuf;
			$bytes += $read_len;

			if ($bytes >= $max_len) {
				$timed_out = 0;
				last;
			}
		}
	}

	$select->remove($child);

	$child->close();

	$output = substr($output, 0, $max_len);

	# subprocess may remain (timeout or max bytes) - give it a nudge
	my $attempts = 10;
	for (; (waitpid($pid, WNOHANG) == 0) && $attempts; $attempts--) {
		kill('INT', $pid); # gentle at first

		sleep(0.1); # Time::HiRes::sleep()
	}

	# all attempts exhausted and it's still running
	if (!$attempts) {
		kill('KILL', $pid); # then firm
		waitpid($pid, WNOHANG);
	}

	if ($timed_out) {
		response(FAILURE, "$$command[0] command exceeded max runtime of $timeout seconds", $output);
	}
	elsif ($bytes >= $max_len) { # shouldn't really happen
		response(FAILURE, "$$command[0] output truncated after $max_len bytes", $output);
	}
	elsif ($? >> 8) {
		response(FAILURE, "$$command[0] command exited with non-zero status " . ($? >> 8), $output);
	}
	else {
		response(SUCCESS, "Success", $output);
	}
}
