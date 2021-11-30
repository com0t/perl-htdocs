#!/usr/bin/perl

use RISC::Collect::Logger;
use Data::Dumper;

use strict;
use warnings;

BEGIN { print('||&||'); }
END { print('||&||'); }

my ($auth, $assesscode, $type) = @ARGV;

my $logger = RISC::Collect::Logger->new('migrate_new_bstrap');

logprint($0 . ': got argv: ' . join(',', @ARGV));

my @bstrap_cmds = (
	"/usr/bin/perl /home/risc/bstrap.pl $auth $assesscode scripts",
	"/usr/bin/perl /home/risc/appliance_migration_scripts/migration_post.pl $auth $assesscode $type",
);

foreach my $cmd (@bstrap_cmds) {
	logprint('running cmd: ' . $cmd);

	my $output = qx($cmd 2>&1);
	logprint('output was: ' . $output);
	($?) and do {
		logprint('abort: non-zero return status from "' . $cmd . '": ' . $?);
		exit(1); # can't proceed - rn150-scripts contain the next step
	}
}

sub logprint {
	print(@_, "\n");
	$logger->info(@_);
}
