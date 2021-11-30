#!/bin/bash

set -e

case "${SSH_ORIGINAL_COMMAND}" in
	"sudo /srv/httpd/htdocs/shell/migrate_data_postprocessing.pl")
		env -i sudo /srv/httpd/htdocs/shell/migrate_data_postprocessing.pl
		;;
	# standard centos rsync 3.0.6
	"rsync --server -logDtpre.iLs . /home/migration/staging")
		env -i rsync --server -logDtpre.iLs . /home/migration/staging
		;;
	# ius rsync 3.1.3
	"rsync --server -logDtpre.iLsfxC . /home/migration/staging")
		env -i rsync --server -logDtpre.iLsfxC . /home/migration/staging
		;;
	"cat /home/migration/staging/riscappliancekey")
		env -i cat /home/migration/staging/riscappliancekey
		;;
	"true")
		env -i true
		;;
	*)
		echo "invalid command: ${SSH_ORIGINAL_COMMAND}"
		exit 1
		;;
esac
