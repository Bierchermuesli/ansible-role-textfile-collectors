#!/bin/sh
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# dma (DragonFly Mail Agent) queue depth and age — the postfix_queue equivalent
# for hosts relaying through dma instead of postfix.
#
# dma keeps one M<id> (message body) and one Q<id> (envelope) per queued mail
# in its spool and unlinks both on successful delivery, so counting M* files is
# the queue depth. Anything still there after a flush run is mail that could
# not be delivered - on these hosts that is cron output and alerts.
set -eu

spool=${DMA_SPOOL:-/var/spool/dma}
[ -d "$spool" ] || exit 0

count=$(find "$spool" -maxdepth 1 -type f -name 'M*' 2>/dev/null | wc -l)

age=0
if [ "$count" -gt 0 ]; then
    oldest=$(find "$spool" -maxdepth 1 -type f -name 'M*' -printf '%T@\n' 2>/dev/null \
             | sort -n | head -1 | cut -d. -f1)
    [ -n "$oldest" ] && age=$(($(date +%s) - oldest))
fi

echo "# HELP dma_queue_messages Number of messages queued in dma's spool."
echo "# TYPE dma_queue_messages gauge"
echo "dma_queue_messages $count"

echo "# HELP dma_queue_oldest_message_age_seconds Age of the oldest queued message, 0 if the queue is empty."
echo "# TYPE dma_queue_oldest_message_age_seconds gauge"
echo "dma_queue_oldest_message_age_seconds $age"
