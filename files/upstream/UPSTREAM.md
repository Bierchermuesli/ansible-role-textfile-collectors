# Vendored upstream collector scripts

Source: https://github.com/prometheus-community/node-exporter-textfile-collector-scripts
Commit: `53d484331170e6f00237f0fbd6f4acae33064b87`
License: Apache-2.0

This is the same collection Debian ships as `prometheus-node-exporter-collectors`
(identical file list). We vendor it instead of installing that package because
the package `Depends: prometheus-node-exporter`, which would drag Debian's
exporter onto hosts where `prometheus.prometheus.node_exporter` already owns
`:9100`.

Only the scripts this fleet uses are vendored. To add another one, fetch it at
the same commit and add an entry to the role's `textfile_collectors_registry`:

    curl -sfO https://raw.githubusercontent.com/prometheus-community/node-exporter-textfile-collector-scripts/53d484331170e6f00237f0fbd6f4acae33064b87/<script>

Scripts are installed unmodified except where listed under "Local patches"
below. To bump: re-fetch all of them at a new commit, update the SHA above,
diff before committing, and re-apply or drop each local patch.

## Local patches

### apt_info.py — dropped

Replaced by our own `files/apt_info.sh` (same metrics, no python-apt; see the
role README). The phasing guard that used to live here went with it.

### deleted_libraries.py — dropped

Replaced by our own `files/deleted_libraries.sh`. Upstream only counts the
first deleted library per process (indentation slip, still on master at the
time of writing); see the role README.
