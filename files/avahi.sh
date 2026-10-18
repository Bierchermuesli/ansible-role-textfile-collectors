#!/bin/bash
# Managed by Ansible (roles/textfile-collectors). Do not edit on the host.
#
# mDNS reflector visibility (roles/avahi). Avahi exposes no statistics of
# its own, so this combines two views:
#   - what the daemon currently knows: avahi-browse over all service types,
#     counted per interface/protocol/type, plus distinct hosts per segment.
#     Interface is the one the record arrived on, so iot-side entries prove
#     that the IoT devices announce and the firewall lets 5353 in.
#   - how much mDNS actually arrives: packet/byte counters of the
#     "mDNS reflector" INPUT rules from roles/iptables. Reset on every
#     rules reload - fine for a counter.
# Per-host labels are opt-in (AVAHI_PER_HOST=1): one series per device and
# protocol is fine for a dozen devices, not for a campus. Service names are
# never exported; `avahi-browse -art` on the host answers "which".
set -u

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

up=0
systemctl is-active --quiet avahi-daemon && up=1
echo "# HELP avahi_up Whether avahi-daemon is active."
echo "# TYPE avahi_up gauge"
echo "avahi_up $up"

browse_ok=0
browse_out=""
start=$(date +%s.%N)
if [ "$up" = 1 ]; then
    # -a all types, -r resolve (gives host/address), -t terminate when the
    # cache has been dumped, -p parsable, -k raw service types instead of
    # the human-readable names from the service-type database.
    if browse_out=$(timeout 45 avahi-browse -artpk 2>/dev/null); then
        browse_ok=1
    fi
fi
end=$(date +%s.%N)

echo "# HELP avahi_browse_success Whether the avahi-browse run completed."
echo "# TYPE avahi_browse_success gauge"
echo "avahi_browse_success $browse_ok"
echo "# HELP avahi_browse_duration_seconds Wall time of the avahi-browse run."
echo "# TYPE avahi_browse_duration_seconds gauge"
awk -v s="$start" -v e="$end" 'BEGIN { printf "avahi_browse_duration_seconds %.3f\n", e - s }'

if [ "$browse_ok" = 1 ]; then
    # Parsable format:  +;iface;proto;name;type;domain            (seen)
    #                   =;iface;proto;name;type;domain;host;addr;port;txt  (resolved)
    echo "# HELP avahi_services Service instances avahi currently knows, by interface and IP protocol the announcement arrived on, and service type."
    echo "# TYPE avahi_services gauge"
    printf '%s\n' "$browse_out" | awk -F';' '
        $1 == "+" { n[$2 ";" $3 ";" $5]++ }
        END { for (k in n) { split(k, a, ";");
              printf "avahi_services{interface=\"%s\",protocol=\"%s\",type=\"%s\"} %d\n", a[1], a[2], a[3], n[k] } }' \
        | sort

    echo "# HELP avahi_hosts Distinct hosts with at least one resolved service, by interface and protocol."
    echo "# TYPE avahi_hosts gauge"
    printf '%s\n' "$browse_out" | awk -F';' '
        $1 == "=" { h[$2 ";" $3 ";" $7] = 1 }
        END { for (k in h) { split(k, a, ";"); n[a[1] ";" a[2]]++ }
              for (k in n) { split(k, a, ";");
              printf "avahi_hosts{interface=\"%s\",protocol=\"%s\"} %d\n", a[1], a[2], n[k] } }' \
        | sort

    if [ "${AVAHI_PER_HOST:-0}" = 1 ]; then
        echo "# HELP avahi_host_services Resolved services per host. protocol is the transport of the announcement; address is whatever the host resolves to, so an IPv6-announcing host without AAAA shows its IPv4."
        echo "# TYPE avahi_host_services gauge"
        printf '%s\n' "$browse_out" | awk -F';' '
            # avahi-browse -p escapes labels: \NNN decimal for bytes outside
            # [a-zA-Z0-9-], e.g. a0\0582c for a0:2c. Undo that first, then
            # escape backslash and quote for the Prometheus text format.
            function unesc(s,   out, c) {
                out = ""
                while (match(s, /\\([0-9][0-9][0-9]|.)/)) {
                    out = out substr(s, 1, RSTART - 1)
                    c = substr(s, RSTART + 1, RLENGTH - 1)
                    out = out (length(c) == 3 ? sprintf("%c", c + 0) : c)
                    s = substr(s, RSTART + RLENGTH)
                }
                return out s
            }
            function esc(s) { s = unesc(s); gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
            $1 == "=" { n[$2 ";" $3 ";" $7 ";" $8]++ }
            END { for (k in n) { split(k, a, ";");
                  printf "avahi_host_services{interface=\"%s\",protocol=\"%s\",host=\"%s\",address=\"%s\"} %d\n",
                         a[1], a[2], esc(a[3]), esc(a[4]), n[k] } }' \
            | sort
    fi

    echo "# HELP avahi_unresolved_services Services seen but not resolvable within the browse run."
    echo "# TYPE avahi_unresolved_services gauge"
    printf '%s\n' "$browse_out" | awk -F';' '
        $1 == "+" { seen++ } $1 == "=" { res++ }
        END { printf "avahi_unresolved_services %d\n", seen - res }'
fi

# Firewall counters: the INPUT rules carry the comment "mDNS reflector" and
# match on -i <interface>. Columns of `-L -v -n -x`:
#   pkts bytes target prot opt in out source destination ... /* comment */
# Caveats: lan88 is shadowed by the catch-all `-i lan88 -j ACCEPT` above it,
# so it stays at 0 there. The rules exclude locally sourced packets - Linux
# loops sent multicast back onto the sending interface, which would count
# avahi's own reflections as device traffic.
if command -v iptables >/dev/null 2>&1; then
    counters=$(for fam in ipv4 ipv6; do
        cmd=iptables; [ "$fam" = ipv6 ] && cmd=ip6tables
        $cmd -w 5 -L INPUT -v -n -x 2>/dev/null | awk -v fam="$fam" '
            /mDNS reflector/ { print fam, $6, $1, $2 }'
    done)
    echo "# HELP avahi_mdns_input_packets_total mDNS packets accepted on UDP/5353 per interface (iptables counter, resets on rules reload)."
    echo "# TYPE avahi_mdns_input_packets_total counter"
    printf '%s\n' "$counters" | awk 'NF { printf "avahi_mdns_input_packets_total{interface=\"%s\",family=\"%s\"} %s\n", $2, $1, $3 }' | sort
    echo "# HELP avahi_mdns_input_bytes_total mDNS bytes accepted on UDP/5353 per interface (iptables counter, resets on rules reload)."
    echo "# TYPE avahi_mdns_input_bytes_total counter"
    printf '%s\n' "$counters" | awk 'NF { printf "avahi_mdns_input_bytes_total{interface=\"%s\",family=\"%s\"} %s\n", $2, $1, $4 }' | sort
fi
