#!/bin/bash
#
## outputs a curl request to orchestration
#

export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"

OUTPUT="/srv/httpd/htdocs/dump/dumpHTTPS.txt"

rm -f "$OUTPUT"

# load proxy, if any
if [ -s "/etc/environment" ]; then
	for ENV in $(cut -d '=' -f1 /etc/environment); do
		[[ "$ENV" =~ ^[a-zA-Z0-9_]+$ ]] || { echo "$0: bad environment" >&2; exit -1; }
		VAL=$(pam_getenv "$ENV")
		[ -n "$VAL" ] && export "$ENV"="$VAL"
	done
fi

# rn150 does not support the no-ssl flag (yet) - just go by the presence of https_proxy as is done elsewhere
[ -n "$https_proxy" ] && NO_SSL="--insecure"

# remove extraneous Expire in lines - fixed upstream, see https://github.com/curl/curl/pull/3558 and https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=926148
curl --verbose --max-time 60 $NO_SSL https://orchestration.riscnetworks.com 2>&1 | egrep -v '^\* Expire in' > "$OUTPUT"
