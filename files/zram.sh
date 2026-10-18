#!/bin/sh
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# zram compression stats. Replaces a hand-rolled zram-metrics.sh root cron,
# with three fixes:
#   - disksize used an unset $dev, so it exported device="" instead of the name
#   - `> file` from cron is not atomic; node_exporter can read a truncated file
#   - samples are grouped per metric family, which the text format expects
#
# mm_stat fields (Documentation/admin-guide/blockdev/zram.rst):
#   orig_data_size compr_data_size mem_used_total mem_limit mem_used_max ...
set -eu

devices=""
for d in /sys/block/zram*; do
    # Unmatched glob stays literal, so check before trusting it.
    [ -d "$d" ] || continue
    devices="$devices $d"
done
[ -n "$devices" ] || exit 0

echo "# HELP zram_data_bytes Uncompressed size of the data stored in this device."
echo "# TYPE zram_data_bytes gauge"
for d in $devices; do
    set -- $(cat "$d/mm_stat")
    printf 'zram_data_bytes{device="%s"} %s\n' "$(basename "$d")" "$1"
done

echo "# HELP zram_compressed_bytes Compressed size of the data stored in this device."
echo "# TYPE zram_compressed_bytes gauge"
for d in $devices; do
    set -- $(cat "$d/mm_stat")
    printf 'zram_compressed_bytes{device="%s"} %s\n' "$(basename "$d")" "$2"
done

echo "# HELP zram_used_bytes Memory allocated for this device, including metadata."
echo "# TYPE zram_used_bytes gauge"
for d in $devices; do
    set -- $(cat "$d/mm_stat")
    printf 'zram_used_bytes{device="%s"} %s\n' "$(basename "$d")" "$3"
done

echo "# HELP zram_disksize_bytes Configured size of this device."
echo "# TYPE zram_disksize_bytes gauge"
for d in $devices; do
    printf 'zram_disksize_bytes{device="%s"} %s\n' "$(basename "$d")" "$(cat "$d/disksize")"
done
