#!/bin/sh
#
## setKeyPermissions.sh
## sets correct ownership and permissions on private keys for gensrvssh
chown root:root /home/risc/keys/*
chmod 400 /home/risc/keys/*
