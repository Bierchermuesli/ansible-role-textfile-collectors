#!/bin/sh
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# Processes still mapping a library that was deleted (replaced by an upgrade),
# i.e. a restart is pending. Shell port of prometheus-community's
# deleted_libraries.py with the same metric and labels:
#
#   node_processes_linking_deleted_libraries{library_path,library_name}
#     number of processes mapping that deleted library
#
# Upstream only records the first deleted library of each process (an
# indentation slip nests the counting under "first time we see this
# process"), so a process holding a stale libssl and libc showed up under one
# of them only. This counts every library.
set -eu
export LC_ALL=C

echo "# HELP node_processes_linking_deleted_libraries Count of running processes that link a deleted library"
echo "# TYPE node_processes_linking_deleted_libraries gauge"

# grep keeps going when a process exits between the glob and the read (status
# 2), unlike mawk, which aborts on the first unreadable file.
# Line: /proc/PID/maps:ADDR PERMS OFFSET DEV INODE PATH (deleted)
grep -H -F ' (deleted)' /proc/[0-9]*/maps 2>/dev/null | awk '
    {
        i = index($0, ":")
        proc = substr($0, 1, i - 1)
        n = split(substr($0, i + 1), f, " ")
        # same filter as upstream: exactly 7 fields, a /lib/ path, "(deleted)"
        if (n != 7 || index(f[6], "/lib/") == 0 || index(f[7], "(deleted)") == 0) next
        if (!((proc, f[6]) in seen)) { seen[proc, f[6]] = 1; count[f[6]]++ }
    }
    END {
        for (lib in count) {
            dir = lib; sub(/\/[^\/]*$/, "", dir)
            base = lib; sub(/^.*\//, "", base)
            gsub(/\\/, "\\\\", dir); gsub(/"/, "\\\"", dir)
            gsub(/\\/, "\\\\", base); gsub(/"/, "\\\"", base)
            printf "node_processes_linking_deleted_libraries{library_path=\"%s\",library_name=\"%s\"} %d\n", dir, base, count[lib]
        }
    }' || true
