#!/bin/sh
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# Drop-in for prometheus-community's apt_info.py with the same metric names, labels and
# semantics, built on dpkg-query and apt-cache instead of python-apt. The
# Python version builds an object per package in the archive (~60k on
# Raspbian), which takes minutes on a Pi 1; apt-cache reads the binary cache.
#
#   apt_upgrades_pending{origin,arch}  installed packages with a newer candidate
#   apt_upgrades_held{origin,arch}     ... of those, dpkg selection "hold"
#   apt_packages_obsolete              installed, candidate from no archive
#   apt_autoremove_pending             what `apt-get autoremove` would remove
#   apt_packages_per_origin{origin,arch}
#   apt_package_cache_timestamp_seconds
#   node_reboot_required
#
# origin is "Origin:Codename/Archive" of every archive offering the candidate
# (sorted, comma-joined, the dpkg status "now" left out), as python-apt has it.
# Phased updates (Ubuntu) are not filtered; Debian and Raspbian don't phase.
set -eu
export LC_ALL=C

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

# Package index -> origin label, from the release lines of `apt-cache policy`:
#  500 http://deb.debian.org/debian trixie/main amd64 Packages
#      release v=13.1,o=Debian,a=stable,n=trixie,l=Debian,c=main,b=amd64
apt-cache policy 2>/dev/null | awk '
    /^ *-?[0-9]+ / && / Packages$/ { idx = $2 " " $3 " " $4; next }
    /^ +release / && idx != "" {
        o = ""; n = ""; a = ""
        k = split(substr($0, index($0, "release ") + 8), kv, ",")
        for (i = 1; i <= k; i++) {
            if (kv[i] ~ /^o=/) o = substr(kv[i], 3)
            else if (kv[i] ~ /^n=/) n = substr(kv[i], 3)
            else if (kv[i] ~ /^a=/) a = substr(kv[i], 3)
        }
        print idx "\t" o ":" n "/" a
        idx = ""
    }' >"$tmp/origins"

# Installed packages: name, architecture, selection (hold or not).
dpkg-query -W -f='${db:Status-Status}\t${binary:Package}\t${Architecture}\t${db:Status-Want}\n' \
    | awk -F'\t' '$1 == "installed" { print $2 "\t" $3 "\t" $4 }' >"$tmp/installed"
# apt-cache policy prints Multi-Arch: same packages without the :arch that
# dpkg-query adds, so join on the bare name.

# One record per installed package: name, installed and candidate version,
# and the origins of the candidate.
cut -f1 "$tmp/installed" | xargs -r apt-cache policy 2>/dev/null | awk -v OFS='\t' '
    FNR == NR { org[$1] = $2; next }
    function flush() {
        if (pkg == "") return
        print pkg, inst, cand, origins
        pkg = ""
    }
    /^[^ ].*:$/ { flush(); pkg = substr($0, 1, length($0) - 1); origins = ""; incand = 0; next }
    /^  Installed: / { inst = $2; next }
    /^  Candidate: / { cand = $2; next }
    /^  Version table:/ { next }
    # version line: "     1.2-3 500" or " *** 1.2-3 500"
    /^ (\*\*\*|   ) [^ ]+ -?[0-9]+$/ { v = ($1 == "***") ? $2 : $1; incand = (v == cand); next }
    incand && /^ +-?[0-9]+ / {
        if ($2 == "/var/lib/dpkg/status") next
        key = $2 " " $3 " " $4
        if (key in org) origins = origins (origins == "" ? "" : "\034") org[key]
    }
    END { flush() }
' FS='\t' "$tmp/origins" FS=' ' - >"$tmp/policy"

# Join with dpkg data and emit the metrics.
awk -F'\t' -v OFS='\t' '
    FNR == NR { n = $1; sub(/:.*$/, "", n); arch[n] = $2; hold[n] = ($3 == "hold"); next }
    {
        name = $1; sub(/:.*$/, "", name)
        if (!(name in arch)) next
        n = split($4, o, "\034")
        # sort and dedupe the origins (n is tiny)
        for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (o[j] < o[i]) { t = o[i]; o[i] = o[j]; o[j] = t }
        label = ""; prev = ""
        for (i = 1; i <= n; i++) if (o[i] != prev) { label = label (label == "" ? "" : ",") o[i]; prev = o[i] }
        print name, arch[name], hold[name], $2, $3, label, n
    }' "$tmp/installed" "$tmp/policy" >"$tmp/joined"


# name arch hold installed candidate origin n_origins
awk -F'\t' '
    function out(metric, help, data, key, k, parts) {
        printf "# HELP %s %s\n# TYPE %s gauge\n", metric, help, metric
        k = 0
        for (key in data) { k++; split(key, parts, SUBSEP)
            gsub(/\\/, "\\\\", parts[1]); gsub(/"/, "\\\"", parts[1])
            printf "%s{origin=\"%s\",arch=\"%s\"} %d\n", metric, parts[1], parts[2], data[key] }
        if (k == 0) printf "%s{origin=\"\",arch=\"\"} 0\n", metric
    }
    {
        upgradable = ($5 != "(none)" && $4 != $5)
        if (upgradable) { pending[$6, $2]++; if ($3) held[$6, $2]++ }
        if ($5 == "(none)" || $7 == 0) obsolete++
        per_origin[$6, $2]++
    }
    END {
        out("apt_upgrades_pending", "Apt packages pending updates by origin", pending)
        out("apt_upgrades_held", "Apt packages pending updates but held back.", held)
        printf "# HELP apt_packages_obsolete Apt packages which are obsolete\n# TYPE apt_packages_obsolete gauge\napt_packages_obsolete %d\n", obsolete
        printf "# HELP apt_packages_per_origin Number of packages installed per origin.\n# TYPE apt_packages_per_origin gauge\n"
        for (key in per_origin) { split(key, parts, SUBSEP)
            gsub(/\\/, "\\\\", parts[1]); gsub(/"/, "\\\"", parts[1])
            printf "apt_packages_per_origin{origin=\"%s\",arch=\"%s\"} %d\n", parts[1], parts[2], per_origin[key] }
    }' "$tmp/joined"

autoremove=$(apt-get -s -o Debug::NoLocking=1 autoremove 2>/dev/null | grep -c '^Remv ' || true)
printf '# HELP apt_autoremove_pending Apt packages pending autoremoval.\n# TYPE apt_autoremove_pending gauge\napt_autoremove_pending %d\n' "$autoremove"

# Same stamp file choice as upstream.
if [ -f /var/lib/apt/periodic/update-success-stamp ]; then
    stamp=/var/lib/apt/periodic/update-success-stamp
elif apt-config shell P APT::Periodic::Update-Package-Lists/b 2>/dev/null | grep -q "P='true'"; then
    stamp=/var/lib/apt/periodic/update-stamp
else
    stamp=/var/lib/apt/lists/partial
fi
printf '# HELP apt_package_cache_timestamp_seconds Apt update last run time.\n# TYPE apt_package_cache_timestamp_seconds gauge\n'
if [ -e "$stamp" ]; then
    printf 'apt_package_cache_timestamp_seconds %s\n' "$(stat -c %Y "$stamp")"
fi

printf '# HELP node_reboot_required Node reboot is required for software updates.\n# TYPE node_reboot_required gauge\nnode_reboot_required %d\n' \
    "$([ -f /run/reboot-required ] && echo 1 || echo 0)"
