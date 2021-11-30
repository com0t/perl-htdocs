use SNMP::Info;
use MIME::Base64;
use lib 'lib';
use RISC::riscUtility;
$|++;

my @parameters;

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("Fail:Unable to decode arguments\n")) {
	@parameters = map {
		$risc_credentials->{$_}
	} qw(test ip passphrase securityname context authtype authpass privType privpass);
# the old fashioned way
} else {
	my $args = shift;
	$args =~/^\'(.+)\'$/;
	@ARGV = split(/\s/, $args);

	@parameters = @ARGV; # :(
}

#database connect
#try
my $mysql = riscUtility::getDBH('risc_discovery',1);

getSNMP(@parameters);

eval {
	my $ipr_dest = $info->ipr_route();
	my $ipr_ifindex = $info->ipr_if();
	my $ipr_1 = $info->ipr_1();
	my $ipr_2 = $info->ipr_2();
	my $ipr_3 = $info->ipr_3();
	my $ipr_4 = $info->ipr_4();
	my $ipr_5 = $info->ipr_5();
	my $ipr_nexthop = $info->ipr_dest();
	my $ipr_type = $info->ipr_type();
	my $ipr_proto = $info->ipr_proto();
	my $ipr_age = $info->ipr_age();
	my $ipr_mask = $info->ipr_mask();
	
	my $ipr_dest2 = $info->ipr_route2();
	my $ipr_ifindex2 = $info->ipr_if2();
	my $ipr_12 = $info->ipr_12();
	my $ipr_22 = $info->ipr_22();
	my $ipr_32 = $info->ipr_32();
	my $ipr_42 = $info->ipr_42();
	my $ipr_52 = $info->ipr_52();
	my $ipr_nexthop2 = $info->ipr_dest2();
	my $ipr_type2 = $info->ipr_type2();
	my $ipr_proto2 = $info->ipr_proto2();
	my $ipr_age2 = $info->ipr_age2();
	my $ipr_mask2 = $info->ipr_mask2();
	
	my $sth15 = $mysql->prepare_cached("INSERT INTO discoverystats (iprange,status,updatetime) values (?,?,?)");
	my $numroutes = 0;
	foreach my $rrid (keys %$ipr_dest) {
		my $route_dest = $ipr_dest->{$rrid};
		my $route_int = $ipr_ifindex->{$rrid};
		my $route_1 = $ipr_1->{$rrid};
		my $route_2 = $ipr_2->{$rrid};
		my $route_3 = $ipr_3->{$rrid};
		my $route_4 = $ipr_4->{$rrid};
		my $route_5 = $ipr_5->{$rrid};
		my $route_nh = $ipr_nexthop->{$rrid};
		my $route_type = $ipr_type->{$rrid};
		my $route_proto = $ipr_proto->{$rrid};
		my $route_age = $ipr_age->{$rrid};
		my $route_mask = $ipr_mask->{$rrid};
		my $slash = maskSlash($route_mask);
		my $routeEntry=$route_dest."/".$slash;
		#print "Adding $routeEntry with time()\n";
		$sth15->execute($routeEntry,5,time()) unless $slash <16 || $route_dest eq '0.0.0.0' || $route_dest =~ /^127\./;
		$numroutes++ unless $slash <16 || $route_dest eq '0.0.0.0' || $route_dest =~ /^127\./;;
	}
	
	if($numroutes == 0) {
		foreach my $rrid (keys %$ipr_dest2) {
			my $route_dest = $ipr_dest2->{$rrid};
			my $route_int = $ipr_ifindex2->{$rrid};
			my $route_1 = $ipr_12->{$rrid};
			my $route_2 = $ipr_22->{$rrid};
			my $route_3 = $ipr_32->{$rrid};
			my $route_4 = $ipr_42->{$rrid};
			my $route_5 = $ipr_52->{$rrid};
			my $route_nh = $ipr_nexthop2->{$rrid};
			my $route_type = $ipr_type2->{$rrid};
			my $route_proto = $ipr_proto2->{$rrid};
			my $route_age = $ipr_age2->{$rrid};
			my $route_mask = $ipr_mask2->{$rrid};
			my $slash = maskSlash($route_mask);
			my $routeEntry=$route_dest."/".$slash;
			$sth15->execute($routeEntry,5,time()) unless $slash <16 || $route_dest eq '0.0.0.0' || $route_dest =~ /^127\./;
			$numroutes++ unless $slash <16 || $route_dest eq '0.0.0.0' || $route_dest =~ /^127\./;;
		}
	}
	
	$sth15->finish();
	print "$numroutes"
}; if ($@) {print "Error: $@";}



sub getSNMPHandle {
	my $orig = shift;
	$orig = decode_base64($orig);
	#my ($version,$ip,$a1,$a2,$a3,$a4,$a5,$a6,$a7) = split(':',$orig);
	eval {
			if ($orig eq '1' || $orig eq '2'){
				my $risc = decode_base64($_[1]);
				$info = new SNMP::Info(
				DestHost => decode_base64($_[0]),
				Community => $risc,
				Version => 1);
			}
	
			if ($orig eq '3') {
				$info = new SNMP::Info(
				DestHost=>decode_base64($_[0]),
				Version=>3,
				SecName=>decode_base64($_[2]),
				SecLevel=>decode_base64($_[1]),
				Context=>decode_base64($_[3]),
				AuthProto=>decode_base64($_[4]),
				AuthPass=>decode_base64($_[5]),
				PrivProto=>decode_base64($_[6]),
				PrivPass=>decode_base64($_[7])
				)
			}
		#IF there is no err, then we know that we can read.  Now we need to test write.
		if (defined $info && defined $info->name()) {
			print "Success:";
		} else {
			print "Fail:No Access";
		}
	}; if ($@) {print "Fail: $@";}
}

sub escape {
	my $string=shift;
	$string=~s/([\/\$\#\%\^\@\&\*\{\}\[\]\<\>\=\+])/\\$1/g;
	return $string;
}

sub maskSlash {
	my $mask = shift;
	my $decimal = ip2bin4($mask);
	my $binary = dec2bin($decimal);
	$size = ($binary =~ tr/1//);
	return $size if defined $size;
}

sub ip2bin4 {
	my $ip = shift;  # ip format: a.b.c.d
	return(unpack("N", pack("C4", split(/\D/, $ip))));
}

sub dec2bin {
	my $str = unpack("B32", pack("N", shift));
	$str =~ s/^0+(?=\d)//;   # otherwise you'll get leading zeros
	return $str;
}

sub getSNMP {
	my $test=riscUtility::decode($_[0]);
	my $ip=riscUtility::decode($_[1]);
	my $version = $test;
	my $passphrase = riscUtility::decode($_[2]);
	my $context=riscUtility::decode($_[4]);
	my $securitylevel = riscUtility::decode($_[2]);
	my $securityname = riscUtility::decode($_[3]);
	my $authtype = riscUtility::decode($_[5]);
	my $authpass = riscUtility::decode($_[6]);
	my $privpass = riscUtility::decode($_[8]);
    if ($version eq '1' || $version eq '2'){
		my $risc = $passphrase;
		$info = new SNMP::Info(
		DestHost => $ip,
		Community => $risc,
		Version => 2);
	} eval {unless (defined $info->name()) {
		my $risc = $passphrase;
		$info = new SNMP::Info(
		DestHost => $ip,
		Community => $risc,
		Version => 1);
	}};
	if ($version eq '3') {
		my $privType;
		my $secLevel;
		my $authType;
		if ($authtype eq 'MD5' || $authtype eq 'SHA') {
			$secLevel=$securitylevel;
			$authType=$authtype;
			if (riscUtility::decode($_[7]) eq 'null') {
				$privType=undef;
			} else {
				$privType=riscUtility::decode($_[7]);
			}
		} else {
			$secLevel=$securitylevel;
			$authType=undef;
			if (riscUtility::decode($_[7]) eq 'null'){
				$privType=undef;
			} else {
				$privType=riscUtility::decode($_[7]);
			}
		}
		if ($context eq 'null') {
			$context=undef;
		};
		$info = new SNMP::Info(
								DestHost=>$ip,
								Version=>3,
								SecName=>$securityname,
								SecLevel=>$securitylevel,
								Context=>$context,
								AuthProto=>$authType,
							
								AuthPass=>$authpass,
								PrivProto=>$privType,
								PrivPass=>$privpass
								)
	}
 #IF there is no err, then we know that we can read.  Now we need to test write.
	if (defined $info && defined $info->name()) {
		print "Success:";
	} else {
		print "Fail:No Access";
	}
}

