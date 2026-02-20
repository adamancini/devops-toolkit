# Snapshots, Backups & Storage Reference

## Snapshot Management

### Create a Snapshot

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "snapname=<SNAP_NAME>&description=<DESCRIPTION>&vmstate=0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot"
```

- `snapname` -- alphanumeric, hyphens, underscores; no spaces
- `vmstate` -- `1` to include RAM state (live snapshot), `0` for disk-only
- Returns a task UPID. Disk-only snapshots are near-instant on LVM-thin.

### List Snapshots

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot" \
  | jq '.data[] | select(.name != "current") | {name, description, snaptime: (.snaptime | todate), vmstate}'
```

The `current` entry represents live state -- filter it out.

### Rollback to Snapshot

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot/<SNAP_NAME>/rollback"
```

**IMPORTANT:** Rollback is destructive -- all changes since the snapshot are lost. VM must be stopped (unless snapshot includes RAM state). Always confirm with user.

### Delete a Snapshot

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot/<SNAP_NAME>"
```

Deletion merges snapshot data back into the parent -- may take time for large snapshots.

### Snapshot Notes

- LVM-thin snapshots are thin-provisioned and space-efficient
- Avoid long snapshot chains (>3-4 deep) -- they degrade I/O performance
- Snapshots are not backups -- they live on the same storage
- With guest agent, filesystem freeze/thaw is automatic during snapshots

## Backup Management

### On-Demand Backup (vzdump)

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "vmid=<VMID>&storage=<BACKUP_STORAGE>&mode=snapshot&compress=zstd&notes-template={{name}}-{{node}}-manual" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/vzdump"
```

- `mode` -- `snapshot` (online), `suspend` (brief pause), `stop` (shuts down during backup)
- `compress` -- `zstd` (recommended), `gzip`, `lzo`, or `0`
- Returns a task UPID

### List Backups

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content?content=backup" \
  | jq '.data[] | {volid, vmid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), ctime: (.ctime | todate), notes}'
```

### List Scheduled Backup Jobs

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/backup" \
  | jq '.data[] | {id, schedule, vmid, storage, mode, compress, enabled}'
```

### Restore from Backup

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "vmid=<NEW_VMID>&archive=<VOLID>&storage=<STORAGE>&unique=1" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu"
```

- `unique=1` -- regenerate MAC addresses to avoid conflicts

### Delete a Backup

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content/<VOLID>"
```

### Backup Notes

- Backups are full copies stored separately -- unlike snapshots, they survive storage failure
- `snapshot` mode is preferred for online VMs -- minimal downtime
- `zstd` offers the best speed-to-ratio tradeoff
- Backup storage must have `content: backup` enabled

## Storage Management

### List Storage Pools

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage" \
  | jq '.data[] | {storage: .storage, type: .type, content: .content, active: .active, avail: (.avail / 1073741824 * 100 | floor / 100 | tostring + "G"), total: (.total / 1073741824 * 100 | floor / 100 | tostring + "G"), used_fraction: (.used_fraction * 100 | floor | tostring + "%")}'
```

### Cluster-Wide Storage Overview

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=storage" \
  | jq '.data[] | {storage: .storage, node: .node, status: .status, avail: (.maxdisk - .disk) / 1073741824 * 100 | floor / 100, total_gb: (.maxdisk / 1073741824 * 100 | floor / 100), used_pct: (.disk / .maxdisk * 100 | floor)}'
```

### List ISOs

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/local/content?content=iso" \
  | jq '.data[] | {volid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), ctime: (.ctime | todate)}'
```

### List VM Disk Images

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content?content=images" \
  | jq '.data[] | {volid, vmid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), format}'
```

### Upload ISO (SSH)

```bash
ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /var/lib/vz/template/iso/<FILENAME>.iso <ISO_URL>'
```

For local files: `scp <LOCAL_ISO_PATH> <SSH_USER>@<NODE_HOST>:/var/lib/vz/template/iso/`

### Identify Orphaned Disks

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.template != 1) | "\(.node) \(.vmid)"' \
  | while read node vmid; do
    unused=$(curl -sk \
      -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
      "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/config" \
      | jq -r '.data | to_entries[] | select(.key | startswith("unused")) | "\(.key): \(.value)"')
    if [ -n "$unused" ]; then
      echo "VMID $vmid ($node): $unused"
    fi
  done
```

### Remove Unused Disk

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "delete=unused0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/config"
```

### Storage Notes

- `local` holds ISOs and container templates (`/var/lib/vz/template/`)
- `local-lvm` is the default thin-provisioned storage for VM disks
- Before cleaning up orphaned disks, verify they are not referenced by snapshots
