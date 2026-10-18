#!/usr/bin/env bash
# Daily: warn if the cert actually served on 443 expires within 14 days (renewal should
# happen at 30 days). Writes /var/lib/paydar/cert-status for the monitoring bot.
DOMAIN=mbn.myp2p.uk
mkdir -p /var/lib/paydar
end=$(echo | timeout 10 openssl s_client -connect 127.0.0.1:443 -servername $DOMAIN 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [[ -z "$end" ]]; then status="ERROR cannot read served cert"
else
    days=$(( ($(date -d "$end" +%s) - $(date +%s)) / 86400 ))
    if (( days < 14 )); then status="WARN served cert expires in $days days ($end)"; else status="OK $days days ($end)"; fi
fi
echo "$(date -u +%FT%TZ) $status" > /var/lib/paydar/cert-status
logger -t paydar-cert "check: $status"
