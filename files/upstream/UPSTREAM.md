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

### apt_info.py — guard `Package.phasing_applied`

Upstream added the phasing filter in 9784008 ("Hide packages if phasing is
being applied", #220) with no version guard. python-apt only exposes that API
since 2.7.11, so on Debian 12 (python-apt 2.6.0) every package raises
AttributeError and the script aborts in its first writer — the host emits no
apt metrics at all, not just no pending-upgrade count.

We compute `hasattr` once at import and fall back to "nothing is phased",
which is what the script did before that commit. Upstream's only fix is in
PR #269, an unmerged rewrite that drops the feature outright; this keeps it
wherever the API exists.

Drop this patch once no Debian 12 hosts are left (bookworm LTS ends
2028-06-30) or once upstream ships its own guard.
