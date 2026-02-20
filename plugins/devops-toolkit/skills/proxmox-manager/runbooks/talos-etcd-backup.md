---
name: talos-etcd-backup
description: Create, rotate, and restore etcd snapshots for Talos Kubernetes clusters
image_type: none
requires: [talosctl]
tested_with:
  talos: "1.9.x"
  kubernetes: "1.32.x"
  proxmox: "8.x"
---

# etcd Snapshot Management

## Parameters

- profile: Cluster profile name (required -- reads endpoints from profile)
- output_path: Path to save the etcd snapshot (default: `<config_dir>/etcd-<date>.snapshot`)
- retention_days: Number of days to retain snapshots (default: 7)
- restore_snapshot: Path to snapshot file for restore operations (required only for restore)

## Prerequisites

- `talosctl` CLI installed and configured with valid talosconfig
- Cluster is healthy (`talosctl health` passes)
- Sufficient disk space for snapshot files (~50-200 MB per snapshot depending on cluster state)

## Steps

### Create Snapshot

1. **Verify cluster health** (local)

   ```bash
   talosctl health
   ```

   Expected result: All health checks pass. Avoid taking snapshots during cluster instability -- the snapshot may capture an inconsistent state.

2. **Create etcd snapshot** (local)

   ```bash
   talosctl etcd snapshot <output_path> \
     --nodes <CP_IP1>
   ```

   Expected result: Snapshot file written to `<output_path>`. The snapshot is taken from the targeted control plane node's local etcd data. Any single healthy CP node will have the full etcd state (etcd replicates across all members).

3. **Verify snapshot** (local)

   ```bash
   ls -lh <output_path>
   ```

   Expected result: File exists with a reasonable size (typically 50-200 MB). A 0-byte file indicates a failed snapshot.

### Automated Backup Script

4. **Create a cron-friendly backup script** (local)

   ```bash
   #!/usr/bin/env bash
   # talos-etcd-backup.sh -- Cron-friendly etcd snapshot with rotation
   set -euo pipefail

   CONFIG_DIR="<config_dir>"
   BACKUP_DIR="${CONFIG_DIR}/etcd-backups"
   RETENTION_DAYS=<retention_days>
   NODE="<CP_IP1>"
   TALOSCONFIG="${CONFIG_DIR}/talosconfig"

   mkdir -p "$BACKUP_DIR"

   SNAPSHOT="${BACKUP_DIR}/etcd-$(date +%Y%m%d-%H%M%S).snapshot"

   export TALOSCONFIG
   talosctl etcd snapshot "$SNAPSHOT" --nodes "$NODE"

   if [ -s "$SNAPSHOT" ]; then
     echo "Snapshot created: $SNAPSHOT ($(du -h "$SNAPSHOT" | cut -f1))"
   else
     echo "ERROR: Snapshot is empty or failed" >&2
     rm -f "$SNAPSHOT"
     exit 1
   fi

   # Rotate old snapshots
   find "$BACKUP_DIR" -name "etcd-*.snapshot" -mtime "+${RETENTION_DAYS}" -delete
   echo "Rotated snapshots older than ${RETENTION_DAYS} days"

   # Report remaining snapshots
   echo "Current snapshots:"
   ls -lh "$BACKUP_DIR"/etcd-*.snapshot 2>/dev/null || echo "  (none)"
   ```

   Schedule with cron (e.g., daily at 2 AM):

   ```
   0 2 * * * /path/to/talos-etcd-backup.sh >> /var/log/etcd-backup.log 2>&1
   ```

### Restore from Snapshot

5. **Disaster recovery -- restore etcd from snapshot** (local)

   **WARNING:** This is a destructive operation. It replaces the entire etcd state with the snapshot contents. All changes since the snapshot was taken will be lost.

   ```bash
   # Stop all control plane nodes' etcd (recovers all members)
   talosctl etcd recover \
     --nodes <CP_IP1>,<CP_IP2>,<CP_IP3> \
     --endpoints <CP_IP1>,<CP_IP2>,<CP_IP3> \
     --snapshot <restore_snapshot>
   ```

   Expected result: etcd is restored from the snapshot on all control plane nodes. The cluster will reconcile to the state captured in the snapshot.

   After recovery, verify:

   ```bash
   talosctl health --wait-timeout 10m
   kubectl get nodes
   kubectl get pods -A
   ```

   Expected result: Cluster healthy, all nodes Ready, workloads running. Some pods may restart as controllers reconcile.

## Cleanup

- Old snapshots are automatically rotated by the backup script (retention_days)
- Manual snapshots in the config directory should be cleaned up after confirming cluster stability

## Notes

- **When to take snapshots:**
  - Before any upgrade (Talos OS or Kubernetes)
  - Before major cluster configuration changes
  - On a regular schedule (daily recommended)
  - Before destructive operations (node removal, etcd member changes)
- **Snapshot storage:** Store snapshots off-cluster. If the Proxmox storage fails, on-cluster snapshots are lost too. Copy snapshots to a remote location (NFS, S3, or another machine).
- **Snapshot size:** etcd snapshots contain all Kubernetes state (pods, services, configmaps, secrets, CRDs, etc.). Size grows with cluster complexity. A typical small cluster produces 50-100 MB snapshots.
- **Single-node snapshot:** A snapshot from any single healthy CP node contains the complete etcd state. You do not need to snapshot all nodes.
- **Restore scope:** `talosctl etcd recover` replaces the etcd data on all targeted nodes. It is designed for disaster recovery when etcd quorum is lost. For single-node recovery, remove the failed node from the etcd cluster and let it rejoin instead.
- **Consistency:** Snapshots are consistent point-in-time copies. etcd guarantees linearizable reads, so the snapshot reflects a consistent state even if taken during active writes.
