#!/usr/bin/env bash
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# Postfix queue depth and age. Not from the upstream collection — it has no
# postfix script, and postfix_exporter is a whole daemon for two numbers.
#
# Counts spool files directly instead of parsing `postqueue -p`: no dependency
# on postfix being able to talk to its own master, which is exactly the
# situation where you want these metrics.
set -euo pipefail

spool=${POSTFIX_SPOOL:-/var/spool/postfix}
[ -d "$spool" ] || exit 0

now=$(date +%s)
queues=(incoming active deferred hold maildrop corrupt)
names=()
counts=()
ages=()

for q in "${queues[@]}"; do
    d="$spool/$q"
    [ -d "$d" ] || continue

    count=$(find "$d" -type f 2>/dev/null | wc -l)
    age=0
    if [ "$count" -gt 0 ]; then
        oldest=$(find "$d" -type f -printf '%T@\n' 2>/dev/null | sort -n | head -1 | cut -d. -f1)
        [ -n "$oldest" ] && age=$((now - oldest))
    fi

    names+=("$q")
    counts+=("$count")
    ages+=("$age")
done

# Samples of one metric family have to be contiguous, so emit family by family.
echo "# HELP postfix_queue_messages Number of messages in a postfix queue."
echo "# TYPE postfix_queue_messages gauge"
for i in "${!names[@]}"; do
    printf 'postfix_queue_messages{queue="%s"} %s\n' "${names[$i]}" "${counts[$i]}"
done

echo "# HELP postfix_queue_oldest_message_age_seconds Age of the oldest message in a postfix queue, 0 if empty."
echo "# TYPE postfix_queue_oldest_message_age_seconds gauge"
for i in "${!names[@]}"; do
    printf 'postfix_queue_oldest_message_age_seconds{queue="%s"} %s\n' "${names[$i]}" "${ages[$i]}"
done
