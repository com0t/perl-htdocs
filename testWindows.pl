#!/usr/bin/perl
#
##
use strict;
use MIME::Base64;

use RISC::riscCreds;

my $cred;
$cred->{'username'} = shift;
$cred->{'passphrase'} = shift;
my $target = decode_base64(shift);

my $credobj = riscCreds->new();
my $res = $credobj->testWin($cred,$target);
print STDOUT join('&',$res->{'status'},$res->{'detail'});
