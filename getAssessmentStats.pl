#!/usr/bin/perl
use MIME::Base64;
use Data::Dumper;
use RISC::riscConfigWeb;
use RISC::riscUtility;
$|++;

riscUtility::loadenv();

my ($user, $pass, $assessmentkey);

# use environment to avoid logging any sensitive strings
if (my $risc_credentials = riscUtility::risc_credentials("Failed to decode arguments\n")) {
	($user, $pass, $assessmentkey) = map {
		$risc_credentials->{$_}
	} qw(user pass assessmentkey);
# the old fashioned way
} else {
	$user = decode_base64(shift);
	$pass = shift;
	$assessmentkey = shift;
}

my $mysql;
eval {$mysql = riscUtility::getDBH('RISC_Discovery',1);};
my $mysqllocal = riscUtility::getDBH('risc_discovery',1);

my $problem = riscConfigWeb::testConnection();
my $status=riscConfigWeb::getAssessmentStats($user,$pass,$assessmentkey) if !defined $problem;

if ( $status->{'status'} && !defined $problem ) {
	my $cStatusStatus = $status->{'status'};
	my $cStatusStatusDetail = $status->{'statusdetail'};
	my $cStatusSubScanned = $status->{'subnets_scanned'};
	my $cStatusSubNotScanned = $status->{'subnets_notscanned'};
	my $cStatusSnmpConfirmed = $status->{'snmp_confirmed'};
	my $cStatusSnmpNotConfirmed = $status->{'snmp_notconfirmed'};
	my $cStatusWinConfirmed = $status->{'windows_confirmed'};
	my $cStatusWinNotCofirmed = $status->{'windows_notconfirmed'};
	my $cStatusVMwareConfirmed = $status->{'vmware_confirmed'};
	my $cStatusVMwareNotConfirmed = $status->{'vmware_notconfirmed'};
	my $cStatusCucmConfirmed = $status->{'cucm_confirmed'};
	my $cStatusCucmNotConfirmed = $status->{'cucm_notconfirmed'};
	my $cStatusCliConfirmed = $status->{'cli_confirmed'};
	my $cStatusCliNotConfirmed = $status->{'cli_notconfirmed'};
	my $cStatusNet = $status->{'netdevices'};
	my $cStatusNetUnknown = $status->{'netdevices_unknown'};
	my $cStatusWinServers = $status->{'winservers'};
	my $cStatusWinWorkstations = $status->{'winworkstations'};
	my $cStatusWinUnknown = $status->{'windevices_unknown'};
	my $cStatusHyperHosts = $status->{'hyperhosts'};
	my $cStatusHyperGuests = $status->{'hyperguests'};
	my $cStatusCucmServers = $status->{'cucmservers'};
	my $cStatusIPPhones = $status->{'ipphones'};
	my $cStatusLinux = $status->{'linuxhosts'};
	my $cStatusGenericNet = $status->{'genericnetwork'};
	my $cStatusScantime = $status->{'scantime'};
	my $cStatusDisplay = $status->{'display'};
	my $cStatusTotalDevs = $status->{'totaldevices'};
	my $cStatusAppStatus = $status->{'appliancestatus'};
	my $cStatusAppIP = $status->{'applianceip'};
	my $cStatusStage = $status->{'stage'};
	my $cStatusAlarm = $status->{'alarmavailable'};
	
	my $pageReturn=buildPage($status);
	print "1&$pageReturn";
} elsif ($status->{'Fault'})  {
	my $errorString = $status->{'Fault'}->{'faultstring'};
	my $errorDetail = $status->{'Fault'}->{'detail'};
	my $errorCode = $status->{'Fault'}->{'faultcode'};
	print "0&$errorString\n";
} elsif ($problem){
	print "3&$problem\n";
}

sub buildPage {
	my $status=shift;
	my $friendlyMessage="<br>";
	my $friendlyState='';
	my $detailInfo;
	my $pageSource;
	my $assessState=$status->{'stage'};
	#define percentage for progressbar based on assessment state
	if ($assessState eq 'Activated' || $assessState eq 'Bootstrap' || $assessState eq 'Initial') {
		$progressPercent='15%';
		$friendlyMessage="The assessment has been created. Please setup and configure the appliance to begin the discovery phase.";
		$friendlyState='Activated';
	}
	if ($assessState eq 'Initial') {
		$progressPercent='15%';
		$friendlyMessage="The appliance is currently intializing.  The discovery scan will begin shortly";
		$friendlyState='Activated';
	}
	if ($assessState eq 'AssetReportsRunning' || $assessState eq 'DataUpload' || $assessState eq 'Discovery' || $assessState eq 'Inventory' || $assessState eq 'Discovery-Pending' || $assessState eq 'Inventory-Pending' || $assessState eq 'RebootInitial') {
			$progressPercent='35%';
#			my $discosRunning=`pgrep disco.pl|wc -l`;
			my $additional="<br>The initial discovery sweep has completed.  You will be notified by email and the assessment will proceed to performance collection when Inventory of newly discovered devices has completed.<br>"
				if ($assessState eq 'AssetReportsRunning' || $assessState eq 'DataUpload' || $assessState eq 'Inventory' || $assessState eq 'Inventory-Pending');
			my $discosRunningQuery=$mysql->selectrow_hashref("select count(*) as numdiscorunning from discoverystats where status=1");
			my $discosRunning=$discosRunningQuery->{'numdiscorunning'};
			my $discoTimeQuery=$mysql->selectrow_hashref("select * from assessmentprogress where phase='Discovery' order by updatetime desc limit 1");
			my $discoTime=$discoTimeQuery->{'updatetime'};
			my $allSubnetsQuery=$mysql->prepare("select distinct(iprange) from discoverystats where (status=2 or status=0 or status=1) and updatetime<$discoTime");
			$allSubnetsQuery->execute();
			my $discosTotal;
			my $totalEndPoints;
			my $totalDevs;
			
			if ($discosTotal<1) {
				my $subnetsQuery2=$mysqllocal->prepare("select distinct(iprange) from discoverystats where status=2 or status=0 or status=1");
				$subnetsQuery2->execute();
				$discosTotal=$subnetsQuery2->rows();
				$totalEndPoints=calcEndpoints($subnetsQuery2);
			} else {
				$discosTotal=$allSubnetsQuery->rows();
				$totalEndPoints=calcEndpoints($allSubnetsQuery);
			}
			
			my $completedSubnetsQuery=$mysql->prepare("select distinct(iprange) from discoverystats where status=2 and updatetime>$discoTime");
			$completedSubnetsQuery->execute();
			my $discosComplete=$completedSubnetsQuery->rows();
			$discosComplete=0 if $discosComplete<0;
			
			if ($discosComplete>0) {
				my $devQuery=$mysql->selectrow_hashref("select sum(devices) as devs from discoverystats where status=2 and updatetime>$discoTime");
				$totalDevs=$devQuery->{'devs'};
			} else {
				$totalDevs=0;
			}
			
			my $completeEndPoints=calcEndpoints($completedSubnetsQuery);
			my $percentComplete=int(100 * ($completeEndPoints / $totalEndPoints));
			$percentComplete = 0 if ($percentComplete > 100); ## XXX hack to avoid understanding why this is sometimes wrong
			$friendlyMessage=	"There are currently $discosRunning subnets being scanned.  Performance analysis will begin when the full discovery process has completed
								<br>NOTE: the information below is updated as each subnet is finished being scanned.";
			$friendlyState='Discovery';
			$detailInfo="<h3>Brief of Discovery Process: $percentComplete\% complete</h3>
					<br>
					<p><span class=\"progress\" style=\"width: 50%\">
							<!-- top and bottom progression marks -->
							<span class=\"top-mark\" style=\"left: 25%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>25%</b></FONT></span></span>
							<span class=\"top-mark\" style=\"left: 50%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>50%</b></FONT></span></span>
	                    	<span class=\"top-mark\" style=\"left: 75%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>75%</b></FONT></span></span>

							<!-- background-text, revealed when progress bar is too small -->
							<span class=\"progress-text\">$percentComplete</span>

							<!-- progress bar with foreground text -->
							<span class=\"progress-bar grey-gradient glossy\" style=\"width: $percentComplete%\">
							<span class=\"stripes\"></span>
	                    	<!-- <span class=\"progress-text\">$percentComplete</span> -->
	                	</span>
	                </span></p>
	                <table cellpadding=\"15\">
	                <tr><td><b>Total Subnets</b></td><td><b>Completed Subnets</b></td><td><b>Total IPs</b></td><td><b>Completed IPs</b></td><td><b>Devices Found</b></td></tr>
	                <tr><td>$discosTotal</td><td>$discosComplete</td><td>$totalEndPoints</td><td>$completeEndPoints</td><td>$totalDevs</td></tr>
	                </table>
	                <p>$additional</p>";
	}
	if ($assessState eq 'PerformanceRunning' || $assessState eq 'PerformanceStopped') {
		$progressPercent='55%';
		$friendlyMessage="The appliance is tracking performance metrics. With the exception of additional scans, the assessment will stay in this state until the end date.  Additional scans or credentials may be added on the appliance at this time by returning to the <B>DASHBOARD</b>.";
		$friendlyState='Performance';
		my $trafficWatchCheck=$mysql->selectrow_hashref("select count(*) as num from netflowtoprn50");
		my $traffic=$trafficWatchCheck->{'num'};
		if ($traffic) {
			$friendlyMessage="<p>The appliances are currently collecting both performance data on the inventoried devices and TrafficWatch data.  Below is diplayed some brief information on the TrafficWatch data being collected.  PLEASE NOTE: the number listed below WILL reset when the appliance uploads information to our NOC (approximately every eight hours).</p>";
			$detailInfo="<h3><u>Brief of TrafficWatch Collection</u></h3>
						";
			my $trafficPktsQuery=$mysql->prepare("select distinct(deviceid) from netflowtoprn50 where samplerid='0.0.0.0'");
			my $trafficFlowQuery=$mysql->prepare("select samplerid,count(*) as num from netflowtoprn50 where samplerid!='0.0.0.0' and samplerid!=''");
			$trafficFlowQuery->execute();
			my $firstLine=$trafficFlowQuery->fetchrow_hashref();
			if (defined($firstLine->{'num'})) {
				$detailInfo.="<b>NetFlow Collection:</b>
								<table>
									<tr><td><b>NetFlow Collector</b></td><td><b>Number of Records</b></td></tr>
									<tr><td>$firstLine->{'samplerid'}</td><td>$firstLine->{'num'}</td></tr>
									";
				while (my $line=$trafficFlowQuery->fetchrow_hashref()) {
					$detailInfo.="<tr><td>$line->{'samplerid'}</td><td>$line->{'num'}</td></tr>
									";
				}
				$detailInfo.="</table>";
			}
			$trafficPktsQuery->execute();
			if ($trafficPktsQuery->rows()>0) {
				$detailInfo.="<b>Mirrored Port Collection:</b>
								<table>
								<tr><td><b>RN50 IP</b></td><td><b>Unique Source Hosts</b></td></tr>";
				while (my $line=$trafficPktsQuery->fetchrow_hashref()) {
					my $devid=$line->{'deviceid'};
					my $trafficPktsDetailQuery=$mysql->selectrow_hashref("select inet_ntoa($devid) as ip,count(distinct(srcaddr)) as num from netflowtoprn50 where deviceid=$devid");
					$detailInfo.="<tr><td>$trafficPktsDetailQuery->{'ip'}</td><td>$trafficPktsDetailQuery->{'num'}</td>"
				}
				$detailInfo.="</table>";
			}
		} else {
			## don't show perf details anymore, as it is unhelpful and doesn't work on the x64 image
			$detailInfo="";
		}
	}
	if ($assessState eq 'FinalReportsRunning' || $assessState eq 'WrapUp-DataUpload' || $assessState eq 'UCELPrep' || $assessState eq 'UCEL-CDS') {
		$progressPercent='75%';
		$friendlyMessage="Final data exports are completing. Please do not power off the appliance at this time. Once finished final reports will be made available.";
		$friendlyState='Wrap-up';
	}
	if ($assessState eq 'Complete') {
		$progressPercent='100%';
		$friendlyMessage="The assessment is complete and final reports are now available.";
		$friendlyState='Complete';
	}	
	$pageSource= "<html>
	                <body>
	                <center>
	                <h2>Assessment Summary</h2>
	                <!-- <p>Your assessment is curently in the <b>$friendlyState Stage</b><br> -->
	                
					 <p><span class=\"progress\" style=\"width: 75%\">
	                        <!-- top and bottom progression marks -->
	                        <span class=\"top-mark\" style=\"left: 15%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>Activated</b></FONT></span></span>
	                        <span class=\"bottom-mark\" style=\"left: 35%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>Discovery</b></FONT></span></span>
	                        <span class=\"top-mark\" style=\"left: 55%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>Performance</b></FONT></span></span>
	                    	<span class=\"bottom-mark\" style=\"left: 75%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>Wrapup</b></FONT></span></span>
							<span class=\"top-mark\" style=\"left: 95%\"><span class=\"mark-label\"><FONT COLOR=\"000000\" size=\"3\"><b>Complete</b></FONT></span></span>

	                        <!-- background-text, revealed when progress bar is too small -->
	                        <span class=\"progress-text\">$progressPercent</span>

	                        <!-- progress bar with foreground text -->
	                        <span class=\"progress-bar green-gradient glossy\" style=\"width: $progressPercent\">
	                        <span class=\"stripes\"></span>
	                    	<!-- <span class=\"progress-text\">$progressPercent</span> -->
	                	</span>
	                </span><p>
	                <br>
	                <p>$friendlyMessage</p>
	                $detailInfo
					Please return to the <b>DASHBOARD</b> in order to update subnets or credentials and request a rescan</p>
					</center>
	                </body>
	                </html>";
	if ($assessState eq 'Error') {
		$pageSource="<html>
	                <body>
	                <center>
	                <h2>Error</h2>
	                <p>There appears to have been an administrative error with your assessment.</p>
	                <p>Please contact us through the community for additional information: https://community.flexera.com/t5/Foundation-CloudScape/ct-p/Foundation-Cloudscape</p>
	                <br><p>NOTE:  This is not a technical error and will have no effect on the appliance or your environment.</p>
	                </center>
	                </body>
	                </html>";
	}
	return $pageSource;
}

sub calcEndpoints {
	my $query=shift;
	my $return;
#	my $subnetsQuery=$mysql->prepare("select * from discoverystats where status=0 or status=2");
#	$query->execute();
	while (my $line=$query->fetchrow_hashref()) {
		$line->{'iprange'}=~/.+\/(\d\d)/;
		my $mask=$1;
		my $numendpoints=2 ** (32-$mask);
		$return+=$numendpoints;
	}
	return $return;
}
