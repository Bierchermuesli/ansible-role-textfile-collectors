# textfile-collectors

[![CI](https://github.com/Bierchermuesli/ansible-role-textfile-collectors/actions/workflows/ci.yml/badge.svg)](https://github.com/Bierchermuesli/ansible-role-textfile-collectors/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Publishes extra metrics into node_exporter's textfile directory. Scripts from
[prometheus-community/node-exporter-textfile-collector-scripts][upstream] are
vendored at a pinned commit (see `files/upstream/UPSTREAM.md`), plus a few of
our own. Each collector runs from its own systemd timer and writes its `.prom`
atomically.

This is what Debian's `prometheus-node-exporter-collectors` package does, minus
its `Depends: prometheus-node-exporter`, which would install Debian's exporter
on hosts where another role (e.g. `prometheus.prometheus.node_exporter`) already
owns `:9100`.

## Requirements

A running node_exporter with the textfile collector enabled, pointed at
`textfile_collectors_dir`. The directory must exist before this role runs.

## Usage

```yaml
- hosts: all
  become: true
  roles:
    - prometheus.prometheus.node_exporter
    - textfile-collectors
```

Pick collectors per host or group:

```yaml
textfile_collectors:
  - apt_info
  - deleted_libraries
  - smartmon
  - zfs_zpool
```

Collectors with a `requires` precondition can be listed everywhere: if the
path is missing the collector is skipped and any leftover units, script and
`.prom` are removed. A host that gains a pool or loses an NVMe self-corrects on
the next run, and the mail queue collectors cost nothing on hosts without a
spool.

Add your own collector without patching the role:

```yaml
textfile_collectors_custom:
  my_thing:
    script: my_thing.sh      # path under the role's files/
    packages: [jq]
    interval: 10min
    requires: /run/my_thing.sock   # optional
    requires_command: "my_thing --version | grep -q 2."   # optional
    env: {MY_THING_VERBOSE: "1"}   # optional, Environment= in the unit
```

`textfile_collectors_custom` merges recursively, so a host can tweak one key
of a built-in collector:

```yaml
textfile_collectors_custom:
  avahi:
    env: {AVAHI_PER_HOST: "1"}
```

## Variables

| Variable | Default | |
|---|---|---|
| `textfile_collectors` | `[apt_info, deleted_libraries, postfix_queue]` | collectors to run |
| `textfile_collectors_dir` | `node_exporter_textfile_dir` or `/var/lib/node_exporter` | where `.prom` files land |
| `textfile_collectors_lib_dir` | `/usr/local/lib/textfile-collectors` | installed scripts |
| `textfile_collectors_randomized_delay` | `5min` | timer jitter |
| `textfile_collectors_registry` | see defaults | built-in collectors |
| `textfile_collectors_custom` | `{}` | merged over the registry |

## Collectors

| name | what it answers | needs |
|---|---|---|
| `apt_info` | pending/held upgrades per origin, reboot required, apt cache age | `python3-apt`, `python3-prometheus-client` |
| `deleted_libraries` | processes still mapping deleted libs, i.e. restart needed | `python3-prometheus-client` |
| `smartmon` | SMART attributes and self-test results | `smartmontools`, real disks |
| `nvme_metrics` | NVMe wear, spare, media errors | `nvme-cli` >= 2.4 |
| `zfs_zpool` | pool health/capacity, dataset usage | zfsutils, a pool |
| `chrony` | offset, stratum, root dispersion | `chronyc` |
| `zram` | compressed/used bytes per zram device | a zram device |
| `postfix_queue` | queue depth and age of oldest message | postfix spool |
| `dma_queue` | same for hosts relaying via dma | dma spool |
| `avahi` | services/hosts an mDNS reflector sees per interface, UDP/5353 firewall counters | [ansible-role-avahi], iptables rules commented `mDNS reflector` |

## Dashboards

Import and pick your Prometheus-compatible datasource in the
`DS_PROMETHEUS` variable.

- `contrib/dashboards/apt.json`: fleet view of `apt_info`. Pending and
  security upgrades, reboots, held packages and apt cache age per host, their
  history, and the installed-package mix per repository origin.
- `contrib/dashboards/avahi.json`: health of the mDNS reflector collector,
  services and hosts per interface, UDP/5353 traffic, and a per-host table
  (needs `AVAHI_PER_HOST=1`).

## Notes

- Output is written by `/usr/local/bin/textfile-collect` via mktemp+mv. A
  failing script leaves the previous `.prom` in place, so its
  `node_textfile_mtime_seconds` goes stale instead of the metrics vanishing.
  Alert on staleness, not on absence.
- Disabling a collector removes its units, script and `.prom`. A leftover
  file would keep exporting its last values forever.
- `apt_info` reports what the apt cache knows, it does not run `apt update`.
  Pair it with `APT::Periodic::Update-Package-Lists "1"`.
- Upstream scripts are Apache-2.0, see `files/upstream/UPSTREAM.md` for the
  pinned commit and local patches.

[upstream]: https://github.com/prometheus-community/node-exporter-textfile-collector-scripts
[ansible-role-avahi]: https://github.com/Bierchermuesli/ansible-role-avahi
