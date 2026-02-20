---
name: proxmox-manager
description: Use when the user asks to "create a proxmox VM", "make a VM template", "migrate VM", "check proxmox status", "evacuate node", "manage proxmox snapshots", "import cloud image", "spin up a cluster", "tear down cluster", "check node health", "list VMs", "clone template", "upload ISO", "manage proxmox storage", "create proxmox API token", "bootstrap proxmox credentials", "bootstrap talos cluster", "deploy talos", "upgrade talos", "talos maintenance mode", "talos IP discovery", "apply talos config", "generate talos secrets", "talos image factory", "talos image cache", "cache container images", "air-gapped talos", "provision VMs", "run provisioning playbook", "talos-provision-vms", "ansible proxmox", "task cluster:deploy", "task cluster:teardown", "task cluster:status", "create VM template", "node maintenance", or mentions Proxmox VE cluster operations, VM lifecycle management, template creation, node maintenance, cluster provisioning, Talos Linux cluster operations, Ansible-driven VM provisioning, Taskfile-based cluster workflows, or Ansible-based host configuration automation.
version: 0.8.0
---

# Proxmox Manager Skill

You are an expert at managing Proxmox VE clusters, with deep knowledge of the Proxmox REST API, VM lifecycle management, cloud-init templates, storage backends, RBAC, live migration, and cluster operations. You manage the cluster defined in `cluster-config.yaml`.

## When to Use This Skill

Invoke this skill when the user asks about:
- Creating, starting, stopping, deleting, or resizing VMs
- Creating VM templates from cloud images, ISOs, or pre-built disk images
- Migrating VMs between nodes or evacuating a node
- Checking cluster, node, or VM status and health
- Managing storage, ISOs, and snapshots
- Bulk operations on VMs by tag
- Spinning up or tearing down entire clusters
- Bootstrapping Proxmox API credentials
- Ingesting new operational procedures from URLs or instructions
- Talos Linux cluster bootstrap, upgrade, or maintenance operations
- Generating Talos secrets, machine configs, or config patches
- Talos Image Factory builds (schematic creation, extension selection)
- Talos image cache creation (pre-caching container images for air-gapped/large-scale deployments)
- Talos node discovery (scanning for maintenance-mode nodes, IP resolution)
- Ansible-driven VM provisioning (`talos-provision-vms.yaml` or similar playbooks)
- Taskfile cluster workflows (`task cluster:deploy`, `task cluster:teardown`, `task cluster:status`)
- Node maintenance mode operations (evacuation, rolling reboots)
- Ansible-based host configuration automation (network, repos, certs, NTP, monitoring, user management)
- Preventing configuration drift across Proxmox nodes at scale

## Cluster Configuration

**CRITICAL:** Before any operation, read the cluster configuration file at:
`skills/proxmox-manager/cluster-config.yaml` (relative to the skill directory)

This file defines the cluster topology, VM defaults, VMID ranges, credential paths, and conventions. Apply these defaults to every operation unless the user explicitly overrides them.

### Key Conventions

All VM defaults (storage, BIOS, CPU, network, SCSI controller, guest agent) and VMID ranges are defined in `cluster-config.yaml` under `defaults` and `vmid_ranges`. Read those values and apply them to every operation unless the user explicitly overrides them.

### VMID Allocation

To find the next available VMID in a range, query all existing VMIDs via the API:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm \
  | jq '[.data[].vmid] | sort'
```

Where `<PASS_PATH>` is `credentials.pass_path` and `<NODE_HOST>` is any `cluster.nodes[].host` from `cluster-config.yaml`.

Then pick the next unused ID within the appropriate range from `vmid_ranges`.

## Credential Security

**NON-NEGOTIABLE RULES -- violations are security incidents:**

1. **NEVER** run `pass show` as a standalone command
2. **NEVER** assign the token to a shell variable that could be echoed or logged
3. **ALWAYS** use `$(pass show ...)` inline within the consuming command
4. **NEVER** use `curl -v` or any verbose mode that leaks HTTP headers
5. **NEVER** display, print, or log the API token value
6. During bootstrap, pipe token output directly into `pass insert` -- never to stdout

### Credential Format

The `pass` entry at `credentials.pass_path` (from `cluster-config.yaml`) stores:
- Line 1: Token ID (e.g., `user@pve!tokenname`)
- Line 2: Token secret (UUID)

### API Call Pattern

Every Proxmox API call follows this pattern. Substitute `<PASS_PATH>` from `credentials.pass_path` and `<NODE_HOST>` from `cluster.nodes[].host` in `cluster-config.yaml`:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/<endpoint>"
```

For POST/PUT/DELETE operations, add the appropriate method and data:

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "param1=value1&param2=value2" \
  "https://<NODE_HOST>:8006/api2/json/<endpoint>"
```

### SSH Pattern

For operations requiring filesystem access on the hypervisor. Substitute `<SSH_USER>` from `credentials.ssh_user` and `<NODE_HOST>` from `cluster.nodes[].host`:

```bash
ssh <SSH_USER>@<NODE_HOST> '<command>'
```

## Execution Model

Use the Proxmox REST API when possible. Fall back to SSH for operations that require filesystem access on the node.

| Method | Operations |
|--------|-----------|
| REST API | VM create, start, stop, resize, migrate, clone, status, snapshot, backup, cluster/node info, tag management, configuration changes |
| SSH | Disk import (`qm set --scsi0 <storage>:0,import-from=<path>`), template conversion (`qm template`), cloud image download (`wget`/`curl`), cloud-init snippet management, ISO uploads to node storage |

### API Connectivity Check

Before any operation, verify API reachability against the first node in `cluster-config.yaml`:

```bash
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
```

Expected: `200`. If `401`, credentials are invalid. If `000`, node is unreachable.

## Core Operations Reference

This section provides concrete API endpoints and examples for the most common operations. All examples use the placeholders defined in `cluster-config.yaml`:
- `<PASS_PATH>` -- `credentials.pass_path`
- `<NODE_HOST>` -- any `cluster.nodes[].host`
- `<CLUSTER_DOMAIN>` -- the domain suffix from `cluster.nodes[].host` (e.g., `annarchy.net`); used in loop constructs where `$node` is a short name from the API
- `<SSH_USER>` -- `credentials.ssh_user`

### Cluster & Node Status

**Cluster health and node membership:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/status" \
  | jq '.data[] | {name, type, online}'
```

Returns cluster name, quorum status, and each node's online state.

**Per-node resource usage:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/status" \
  | jq '{cpu: .data.cpu, memory_used: .data.memory.used, memory_total: .data.memory.total, uptime: .data.uptime}'
```

Replace `<NODE_NAME>` with the node's short name (e.g., `pve01`). Returns CPU load (0-1 float), memory bytes, and uptime in seconds.

### VM Status & Listing

**List all VMs across the cluster:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '.data[] | {vmid, name, status, node, maxcpu: .maxcpu, maxmem: (.maxmem / 1073741824 | floor | tostring + "G"), template}'
```

**Individual VM status:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/current" \
  | jq '.data | {status, pid, cpu, mem, maxmem, uptime, qmpstatus}'
```

**Filter VMs by status:**

```bash
# Running VMs only
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.status == "running") | {vmid, name, node}]'
```

**List templates:**

```bash
# By template flag
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.template == 1) | {vmid, name, node}]'
```

Templates can also be identified by tag (see `tags.templates` in `cluster-config.yaml`), or by VMID range -- templates use VMIDs in the `vmid_ranges.templates` range.

### VM Creation from Template (Clone)

**Full clone from an existing template:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "newid=<NEW_VMID>&name=<VM_NAME>&full=1&target=<TARGET_NODE>&storage=<STORAGE>" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<TEMPLATE_NODE>/qemu/<TEMPLATE_VMID>/clone"
```

Parameters:
- `newid` -- VMID for the new VM (allocate from `vmid_ranges.vms`)
- `name` -- hostname for the new VM
- `full` -- `1` for a full (independent) clone; omit or `0` for linked clone
- `target` -- destination node name (omit to clone on the same node)
- `storage` -- target storage (use `defaults.storage` from cluster-config)

The clone endpoint returns a task UPID. Poll `GET /nodes/<NODE_NAME>/tasks/<UPID>/status` until `status == "stopped"` and `exitstatus == "OK"`.

**Post-clone configuration (CPU, memory, network, cloud-init):**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "cores=<CORES>&memory=<MEM_MB>&net0=virtio,bridge=<BRIDGE>&ipconfig0=ip=dhcp&ciuser=<CI_USER>&sshkeys=<URL_ENCODED_KEYS>" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<NEW_VMID>/config"
```

Notes:
- `memory` is in MB (e.g., `4096` for 4 GB)
- `sshkeys` must be URL-encoded (use `jq -sRr @uri < ~/.ssh/authorized_keys`)
- `ciuser` defaults to `cloudinit.default_user` from cluster-config
- Apply `defaults.network_bridge` from cluster-config unless overridden

### VM Start / Stop / Shutdown / Reboot

All power operations are POST requests to the VM's status endpoint. They return a task UPID.

**Start:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/start"
```

**Shutdown (graceful via ACPI):**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/shutdown"
```

Sends an ACPI shutdown signal. Requires the QEMU guest agent (`defaults.guest_agent: true`) or ACPI support in the guest OS. The VM may take time to shut down gracefully.

**Stop (immediate -- use with caution):**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/stop"
```

Equivalent to pulling the power cord. May cause data loss or filesystem corruption. Prefer `shutdown` unless the VM is unresponsive.

**Reboot:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/reboot"
```

### VM Deletion

**Delete a VM and its disks:**

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>?purge=1&destroy-unreferenced-disks=1"
```

Parameters:
- `purge=1` -- remove the VM from backup jobs, replication, and HA configuration
- `destroy-unreferenced-disks=1` -- delete any orphaned disk images

**IMPORTANT:** This is a destructive, irreversible operation. Before executing:
1. Confirm the VMID and VM name with the user
2. Verify the VM is stopped (stop it first if running)
3. Never delete VMs in the `vmid_ranges.templates` range without explicit confirmation

### VM Resize

**CPU and memory (config change):**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "cores=<CORES>&memory=<MEM_MB>" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/config"
```

- CPU cores and memory can be changed while the VM is stopped and take effect on next start
- CPU hotplug: works if the VM's `hotplug` config includes `cpu` (not enabled by default)
- Memory hotplug: works if `hotplug` includes `memory` and the guest OS supports DIMM hotplug (not common)
- **In practice, stop the VM before resizing CPU or memory**

**Disk resize (grow only):**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "disk=scsi0&size=+10G" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/resize"
```

- `disk` -- the disk name (e.g., `scsi0`, `virtio0`, `efidisk0`)
- `size` -- prefix with `+` to grow by that amount (e.g., `+10G`), or specify absolute size (e.g., `50G`)
- **Disks can only be grown, never shrunk**
- Disk resize can be performed while the VM is running (hot-resize)
- The guest OS must expand its filesystem to use the new space (e.g., `growpart` + `resize2fs`, or cloud-init will handle it on reboot for cloud images)

### Task Polling

Many operations (clone, migrate, backup) return a task UPID rather than completing synchronously. Poll for completion:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/tasks/<UPID>/status" \
  | jq '{status: .data.status, exitstatus: .data.exitstatus}'
```

- `status == "running"` -- task still in progress
- `status == "stopped"` and `exitstatus == "OK"` -- task completed successfully
- `status == "stopped"` and `exitstatus != "OK"` -- task failed; check `.data.exitstatus` for details

Read task logs for debugging:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/tasks/<UPID>/log?limit=50" \
  | jq '.data[] | .t'
```

### Migration

**Live migrate a running VM to another node:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "target=<TARGET_NODE>&online=1" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<SOURCE_NODE>/qemu/<VMID>/migrate"
```

Parameters:
- `target` -- destination node name (e.g., `pve02`)
- `online` -- `1` for live migration (VM stays running), `0` for offline migration

Returns a task UPID. Poll with the task polling pattern until `status == "stopped"` and `exitstatus == "OK"`.

**Offline migrate a stopped VM:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "target=<TARGET_NODE>&online=0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<SOURCE_NODE>/qemu/<VMID>/migrate"
```

Use offline migration when:
- The VM is stopped
- The VM uses local storage that cannot be live-migrated
- You need to move the disk data between storage backends

**Pre-migration check -- verify target node has sufficient resources:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<TARGET_NODE>/status" \
  | jq '{cpu: .data.cpu, memory_free: ((.data.memory.total - .data.memory.used) / 1073741824 | floor | tostring + "G"), memory_total: (.data.memory.total / 1073741824 | floor | tostring + "G")}'
```

**Notes:**
- Live migration requires shared storage or local-to-local migration support (PVE 7.2+)
- With `local-lvm` storage, Proxmox performs storage migration automatically (copies disk data over the network)
- Migration speed depends on VM memory size and disk dirty rate
- For VMs with large memory footprints, consider setting a migration bandwidth limit via the `bwlimit` parameter (in KiB/s)

### Bulk Tag Operations

**List VMs filtered by tag:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | {vmid, name, status, node, tags}]'
```

Tags in the API response are semicolon-delimited (e.g., `"template;cloudinit"`). Use `split(";")` for exact matching rather than `test()` to avoid partial matches (e.g., "k8s" matching "k8s-staging").

**List VMs filtered by multiple tags (AND logic -- must have all tags):**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select((.tags // "" | split(";")) as $t | ("<TAG1>" | IN($t[])) and ("<TAG2>" | IN($t[]))) | {vmid, name, status, node, tags}]'
```

**Start all VMs matching a tag:**

```bash
# First, get the list of stopped VMs with the tag
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | select(.status == "stopped") | "\(.node) \(.vmid)"')

# Then start each VM
echo "$VMS" | while read node vmid; do
  [ -z "$node" ] && continue
  echo "Starting VMID $vmid on $node..."
  curl -sk -X POST \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/status/start"
done
```

**Shutdown all VMs matching a tag (graceful):**

```bash
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | select(.status == "running") | "\(.node) \(.vmid)"')

echo "$VMS" | while read node vmid; do
  [ -z "$node" ] && continue
  echo "Shutting down VMID $vmid on $node..."
  curl -sk -X POST \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/status/shutdown"
done
```

**Apply a tag to multiple VMs by VMID list:**

```bash
for vmid in <VMID1> <VMID2> <VMID3>; do
  # Get current node and tags
  INFO=$(curl -sk \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
    | jq -r ".data[] | select(.vmid == $vmid) | \"\(.node) \(.tags // \"\")\"")
  node=$(echo "$INFO" | awk '{print $1}')
  existing_tags=$(echo "$INFO" | cut -d' ' -f2-)
  # Append new tag (semicolon-separated for API)
  if [ -n "$existing_tags" ]; then
    new_tags="${existing_tags};<NEW_TAG>"
  else
    new_tags="<NEW_TAG>"
  fi
  curl -sk -X PUT \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    -d "tags=$new_tags" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/config"
done
```

**Remove a tag from all VMs that have it:**

```bash
VMS=$(curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq -r '.data[] | select(.tags // "" | split(";") | any(. == "<TAG>")) | "\(.node) \(.vmid) \(.tags)"')

echo "$VMS" | while read node vmid tags; do
  [ -z "$node" ] && continue
  new_tags=$(echo "$tags" | tr ';' '\n' | grep -v "^<TAG>$" | paste -sd ';' -)
  curl -sk -X PUT \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    -d "tags=$new_tags" \
    "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/qemu/$vmid/config"
done
```

**Notes:**
- Always preview the affected VMs before executing bulk operations (dry-run first)
- For destructive bulk operations (stop, delete), confirm with the user and list all affected VMs by name and VMID
- The `<NODE_HOST>` in bulk queries should target any cluster node -- `cluster/resources` returns cluster-wide data regardless of which node you query

### Snapshot Management

**Create a snapshot:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "snapname=<SNAP_NAME>&description=<DESCRIPTION>&vmstate=0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot"
```

Parameters:
- `snapname` -- snapshot identifier (alphanumeric, hyphens, underscores; no spaces)
- `description` -- human-readable description (URL-encode if it contains special characters)
- `vmstate` -- `1` to include RAM state (live snapshot), `0` for disk-only snapshot

Returns a task UPID. Disk-only snapshots are near-instant on LVM-thin. RAM snapshots take longer and briefly pause the VM.

**List all snapshots for a VM:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot" \
  | jq '.data[] | select(.name != "current") | {name, description, snaptime: (.snaptime | todate), vmstate}'
```

The `current` entry represents the live state and should be filtered out. `snaptime` is a Unix timestamp.

**Rollback to a snapshot:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot/<SNAP_NAME>/rollback"
```

**IMPORTANT:** Rollback is destructive -- all changes since the snapshot are lost. The VM must be stopped before rollback (unless the snapshot includes RAM state). Always confirm with the user before executing.

Returns a task UPID. Poll for completion.

**Delete a snapshot:**

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/snapshot/<SNAP_NAME>"
```

Returns a task UPID. Snapshot deletion merges the snapshot data back into the parent, which may take time for large snapshots.

**Notes:**
- Snapshots on LVM-thin (`local-lvm`) are thin-provisioned and space-efficient
- Avoid long snapshot chains (>3-4 deep) -- they degrade I/O performance and complicate merges
- Snapshots are not backups -- they live on the same storage as the VM. Use vzdump for true backups
- For consistent snapshots of running VMs, the QEMU guest agent enables filesystem freeze/thaw (`fsfreeze-freeze` / `fsfreeze-thaw`) automatically during the snapshot operation

### Backup Management

**Trigger an on-demand backup (vzdump):**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "vmid=<VMID>&storage=<BACKUP_STORAGE>&mode=snapshot&compress=zstd&notes-template={{name}}-{{node}}-manual" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/vzdump"
```

Parameters:
- `vmid` -- VMID to back up (can be a comma-separated list for multiple VMs)
- `storage` -- target storage for the backup file (must support `content: backup`)
- `mode` -- `snapshot` (online, uses QEMU snapshot), `suspend` (brief pause), or `stop` (shuts down VM during backup)
- `compress` -- `zstd` (recommended), `gzip`, `lzo`, or `0` for none
- `notes-template` -- template for backup notes; supports `{{name}}`, `{{node}}`, `{{vmid}}`, `{{guestname}}`

Returns a task UPID. Backup duration depends on disk size and compression.

**List backups in storage:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content?content=backup" \
  | jq '.data[] | {volid, vmid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), ctime: (.ctime | todate), notes}'
```

**List scheduled backup jobs:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/backup" \
  | jq '.data[] | {id, schedule, vmid, storage, mode, compress, enabled}'
```

**Restore a VM from backup:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "vmid=<NEW_VMID>&archive=<VOLID>&storage=<STORAGE>&unique=1" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu"
```

Parameters:
- `vmid` -- VMID for the restored VM (allocate from `vmid_ranges.vms`)
- `archive` -- the backup volume ID from the storage listing (e.g., `local:backup/vzdump-qemu-1000-2026_02_07-12_00_00.vma.zst`)
- `storage` -- target storage for the restored disks
- `unique` -- `1` to regenerate unique properties (MAC addresses, etc.) to avoid conflicts

Returns a task UPID. Restore duration depends on backup size.

**Delete a backup:**

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content/<VOLID>"
```

Replace `<VOLID>` with the full volume ID (URL-encode the path separators if needed).

**Notes:**
- Backups are full copies stored separately from the VM -- unlike snapshots, they survive storage failure
- `snapshot` mode is preferred for online VMs -- it uses QEMU's snapshot capability with minimal downtime
- With guest agent enabled, filesystem freeze is automatic during snapshot-mode backups
- `zstd` compression offers the best speed-to-ratio tradeoff for modern hardware
- Backup storage must have `content: backup` enabled in its Proxmox storage configuration

### Storage Management

**List all storage pools on a node:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage" \
  | jq '.data[] | {storage: .storage, type: .type, content: .content, active: .active, avail: (.avail / 1073741824 * 100 | floor / 100 | tostring + "G"), total: (.total / 1073741824 * 100 | floor / 100 | tostring + "G"), used_fraction: (.used_fraction * 100 | floor | tostring + "%")}'
```

**Cluster-wide storage overview:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=storage" \
  | jq '.data[] | {storage: .storage, node: .node, status: .status, avail: (.maxdisk - .disk) / 1073741824 * 100 | floor / 100, total_gb: (.maxdisk / 1073741824 * 100 | floor / 100), used_pct: (.disk / .maxdisk * 100 | floor)}'
```

**List ISOs in node storage:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/local/content?content=iso" \
  | jq '.data[] | {volid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), ctime: (.ctime | todate)}'
```

**List VM disk images in storage:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/<STORAGE>/content?content=images" \
  | jq '.data[] | {volid, vmid, size: (.size / 1073741824 * 100 | floor / 100 | tostring + "G"), format}'
```

**Upload an ISO to node storage** (SSH -- the API upload endpoint requires multipart form which is cumbersome from curl):

```bash
ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /var/lib/vz/template/iso/<FILENAME>.iso <ISO_URL>'
```

For local files, use `scp`:

```bash
scp <LOCAL_ISO_PATH> <SSH_USER>@<NODE_HOST>:/var/lib/vz/template/iso/<FILENAME>.iso
```

After upload, verify:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/storage/local/content?content=iso" \
  | jq '.data[] | select(.volid | test("<FILENAME>"))'
```

**Identify orphaned (unused) disks:**

Orphaned disks appear as `unused0`, `unused1`, etc. in VM configs, or as disk images in storage not referenced by any VM.

```bash
# Check for unused disks in VM configs across the cluster
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

**Remove an unused disk from a VM:**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "delete=unused0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/config"
```

This deletes the `unused0` disk entry and the underlying disk image. Adjust the index (`unused0`, `unused1`, etc.) as needed.

**Notes:**
- `local` storage holds ISOs and container templates (`/var/lib/vz/template/`)
- `local-lvm` is the default thin-provisioned storage for VM disks
- Storage usage reporting may show thin-provisioned usage (allocated vs actually written)
- Before cleaning up orphaned disks, verify they are not referenced by snapshots

### Cluster Lifecycle Operations

Cluster lifecycle operations use cluster profiles (defined in `skills/proxmox-manager/clusters/`) to create, query, and destroy entire clusters as a unit. All operations filter VMs by the profile's tag list using AND logic.

**List cluster profiles:**

Read all `.yaml` files in the `clusters/` directory to see available profiles:

```bash
ls skills/proxmox-manager/clusters/*.yaml
```

**Cluster status -- list VMs belonging to a cluster:**

Query all VMs whose tags match every tag in the profile (AND logic). This returns only VMs that are members of the specified cluster:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.template != 1) | select((.tags // "" | split(";")) as $t | ("talos" | IN($t[])) and ("kubernetes" | IN($t[])) and ("staging" | IN($t[]))) | {vmid, name, status, node, tags}]'
```

Replace the tag literals with the profile's `tags` list. The `select(.template != 1)` filter excludes templates from cluster membership queries.

**Cluster create:**

Full cluster provisioning is a multi-step procedure documented in `runbooks/cluster-create.md`. Summary:

1. Read the cluster profile
2. Allocate VMIDs (auto or from explicit assignments)
3. Clone VMs from the template
4. Configure each VM (CPU, memory, disk, tags)
5. Start all VMs
6. Bootstrap Talos (if `type: talos`) -- generate configs, apply, bootstrap
7. Bootstrap Flux CD (if `flux` section present)

See the runbook for full API commands, task polling, and verification steps.

**Cluster teardown:**

Cluster teardown destroys all VMs matching the profile's tags. Documented in `runbooks/cluster-teardown.md`. Summary:

1. Read the cluster profile
2. List all VMs matching the profile's tags (AND logic)
3. Confirm the destruction plan with the user
4. Gracefully shut down running VMs (force-stop after timeout)
5. Delete all VMs with `purge=1&destroy-unreferenced-disks=1`
6. Verify no VMs remain with those tags

See the runbook for full API commands and safety checks.

**Cluster rebuild:**

A rebuild is a compound operation: teardown followed by create. There is no separate runbook -- execute `cluster-teardown.md` then `cluster-create.md` using the same profile. This is the standard workflow for reprovisioning a cluster from scratch (e.g., after a Talos version upgrade or configuration change).

## RBAC Bootstrap

If credentials do not exist in `pass` (first-time setup), walk the user through this bootstrap procedure. **This requires SSH access to one Proxmox node.** Substitute `<SSH_USER>`, `<NODE_HOST>`, and `<PASS_PATH>` from `cluster-config.yaml`. Choose a PVE username, role name, and token name appropriate for the deployment.

```bash
# 1. Create PVE-realm service account
ssh <SSH_USER>@<NODE_HOST> 'pveum user add <PVE_USER>@pve'

# 2. Create custom role with scoped privileges
ssh <SSH_USER>@<NODE_HOST> 'pveum role add <ROLE_NAME> --privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType \
   VM.PowerMgmt VM.Console VM.Migrate VM.Snapshot VM.Snapshot.Rollback \
   VM.Backup VM.Audit VM.GuestAgent.Audit \
   Datastore.Allocate Datastore.AllocateSpace Datastore.Audit \
   SDN.Use Sys.Audit Sys.Console"'

# 3. Assign permissions at cluster root
ssh <SSH_USER>@<NODE_HOST> 'pveum acl modify / --user <PVE_USER>@pve --role <ROLE_NAME>'

# 4. Create API token -- secret piped directly into pass, never displayed
ssh <SSH_USER>@<NODE_HOST> 'pveum user token add <PVE_USER>@pve <TOKEN_NAME> --privsep 0 --output-format json' \
  | jq -r '"<PVE_USER>@pve!<TOKEN_NAME>\n" + .value' \
  | pass insert -m <PASS_PATH>

# 5. Verify token works
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
```

Expected final output: `200`

**Excluded privileges (by design):**
- `Sys.Modify`, `Sys.PowerMgmt` -- cannot modify host configs or reboot nodes
- `Permissions.Modify` -- cannot escalate privileges
- `User.Modify` -- cannot create/modify users
- `Realm.*` -- cannot change authentication settings

## Runbook System

Runbooks live in `skills/proxmox-manager/runbooks/`. Each runbook is a markdown file encoding an operational procedure with YAML frontmatter.

### Reading Runbooks

At invocation, read all `.md` files in the runbooks directory to know what procedures are available. Reference them when the user asks to perform a matching operation.

### Runbook Format

See `runbooks/_template.md` for the standard format. Each runbook defines:
- Parameters (with defaults where appropriate)
- Step-by-step procedure
- Which steps use API vs SSH
- Cleanup actions

### Ingesting New Runbooks

When the user provides a URL or raw instructions for a new procedure:
1. Fetch/read the source material
2. Identify steps that need adaptation to cluster conventions (storage backend, VMID range, network, BIOS, etc.)
3. Write a new runbook file with cluster defaults applied
4. Show the adapted runbook to the user for confirmation before saving

## Cluster Profiles

Cluster profiles live in `skills/proxmox-manager/clusters/`. Each profile defines an entire cluster -- its nodes, sizing, network, template, tags, and optional bootstrap configuration -- as a single YAML file. Profiles enable repeatable create/destroy cycles: read the profile, provision VMs to match, tear them down when done.

### Profile Schema

```yaml
# Required: unique cluster name (must match the filename without extension)
name: my-cluster
# Required: cluster type -- determines bootstrap behavior
# "talos" enables Talos + Flux bootstrap; "generic" skips bootstrap steps
type: talos | generic

# Talos-specific configuration (required when type: talos)
talos:
  version: "1.9"                    # Talos release version
  kubernetes_version: "1.32.0"      # Target Kubernetes version
  config_dir: /path/to/talos/config # Directory for generated machine configs
  secrets_file: secrets.yaml        # Secrets file relative to config_dir
  factory:
    schematic_id: "abc123..."       # Image Factory schematic hash (64-char hex)
    extensions:                     # System extensions baked into the image
      - siderolabs/qemu-guest-agent
      - siderolabs/iscsi-tools
  patches_dir: patches/             # Per-node config patches relative to config_dir
  vip:
    interface: eth0                 # Network interface for VIP
    ip: 10.0.0.30                   # Virtual IP for HA control plane API

# Network configuration
network:
  api_endpoint: 10.0.0.30           # Kubernetes API VIP or first CP address
  pod_cidr: 10.244.0.0/16           # Pod network CIDR
  service_cidr: 10.96.0.0/12        # Service network CIDR

# Node groups
nodes:
  controlplane:
    count: 3                         # Number of control plane nodes
    name_prefix: k0s                 # Hostname prefix (suffixed with 01, 02, ...)
    cores: 4                         # vCPU cores per node
    memory: 8192                     # Memory in MB per node
    disk: 100G                       # Root disk size per node
    start_vmid: 1031                 # First VMID (auto-increment for remaining)
    placement: spread | pack         # Placement strategy across hypervisors
    assignments:                     # Explicit per-node assignments (optional)
      - name: k0s01
        node: pve01                  # Target Proxmox node
        vmid: 1031                   # Explicit VMID
        ip: 10.0.0.31               # Static IP address
  workers:
    count: 0                         # Number of worker nodes (0 = none)
    name_prefix: k0w
    cores: 4
    memory: 8192
    disk: 100G
    start_vmid: 1041
    placement: spread
    assignments: []                  # Empty when count is 0

# VM template VMID to clone from (must exist in the cluster)
template: 101

# Tags applied to every VM in this cluster
tags:
  - talos
  - kubernetes
  - staging

# Flux CD configuration (optional; used when type: talos)
flux:
  repo: git@github.com:user/fleet-infra.git  # Git repository URL
  path: clusters/staging                       # Path within the repo
  branch: main                                 # Branch to reconcile
```

### Profile Conventions

**Note:** Cluster profiles contain environment-specific values (domain names, repository URLs, IP addresses). The `talos-staging.yaml` profile is a working example for the annarchy.net cluster. When creating new profiles, substitute values appropriate for your environment.

**Naming:** The YAML filename must match the `name` field (e.g., `talos-staging.yaml` for `name: talos-staging`).

**Tags:** Every VM in the cluster receives the tags listed in the profile. During creation, role-specific tags (`controlplane` or `worker`) are appended automatically. Tags are the primary mechanism for identifying cluster membership -- teardown and status queries filter by tag.

**Placement strategies:**
- `spread` -- distribute VMs across hypervisor nodes round-robin to maximize fault tolerance. Preferred for production and staging clusters.
- `pack` -- place VMs on the fewest nodes possible to conserve resources. Useful for dev/test clusters on constrained hardware.

**VMID allocation:**
- When `assignments` are provided, use the explicit VMIDs.
- When `assignments` are empty, auto-allocate starting from `start_vmid` and incrementing by 1. Verify each VMID is unused before allocation.
- VMIDs must fall within `vmid_ranges.vms` from `cluster-config.yaml`.

**Template requirements:** The `template` VMID must reference an existing template in the cluster. For Talos clusters, this is typically a Talos OS cloud image converted to a template. The template must be accessible from all target nodes (either on shared storage or cloned to each node).

**Isolation rules:**
- Clusters must use non-overlapping VMID ranges to avoid conflicts.
- Each cluster should have at least one unique tag (typically matching the cluster name) to enable unambiguous tag-based queries.
- Flux paths must be distinct per cluster to prevent reconciliation conflicts (e.g., `clusters/staging/` vs `clusters/production/`).
- Network CIDRs (`pod_cidr`, `service_cidr`) must not overlap between clusters sharing the same L2 network.

## Talos Linux Operations

Talos Linux is an immutable, API-driven Kubernetes OS. There is no SSH access -- all management is through `talosctl` and the Talos API (port 50000). Machine config is the single source of truth for node configuration.

### Key Concepts

- **Immutable OS:** No SSH, no shell, no package manager. All configuration is declarative via machine configs.
- **Machine config:** A single YAML document that fully defines a node's identity, network, extensions, and Kubernetes role. Applied via `talosctl apply-config`.
- **Factory images:** Talos images are built at `factory.talos.dev` with extensions baked in at build time. Extensions cannot be added at runtime -- a new image must be built.
- **VIP failover:** Control plane nodes share a Virtual IP for the Kubernetes API endpoint. Talos handles ARP-based failover automatically -- no external load balancer needed.
- **Config patches:** Per-node customization (hostname, static IP, VIP) via strategic merge patches or JSON6902 patches applied at `talosctl apply-config` or `talosctl gen config` time.
- **A/B partitions:** Talos maintains two OS partitions for safe upgrades and automatic rollback on boot failure.

### Image Factory

Talos Image Factory (`factory.talos.dev`) builds custom images with system extensions. See `runbooks/talos-image-factory.md` for the full procedure.

**Common extensions for PVE:**
- `siderolabs/qemu-guest-agent` -- **required** for Proxmox integration (graceful shutdown, IP reporting)
- `siderolabs/iscsi-tools` -- required for iSCSI-based CSI drivers
- `siderolabs/util-linux-tools` -- provides `lsblk` and disk utilities

**Schematic ID:** A 64-character hex hash encoding the exact extension set. Same input always produces the same ID. Store in the cluster profile's `talos.factory.schematic_id` for reproducibility.

**Image URLs:**
- Template image: `factory.talos.dev/image/<SCHEMATIC_ID>/v<VERSION>/nocloud-amd64.raw.xz`
- Upgrade installer: `factory.talos.dev/installer/<SCHEMATIC_ID>:v<VERSION>`

### Image Cache

Talos supports a local image cache that stores container images on-disk within a dedicated IMAGECACHE partition. At boot, a `registryd` service serves images from this cache on `127.0.0.1`, eliminating external registry pulls. This is critical for:
- **Air-gapped environments** where nodes cannot reach external registries
- **Bandwidth-limited edge** where repeated pulls are expensive
- **Large-scale deployments** (100+ clusters) where simultaneous pulls DDoS the registry

The cache is built at image creation time using `talosctl images cache-create` and embedded via the Talos imager's `--image-cache` flag. It must be enabled in the machine config before bootstrap:

```yaml
machine:
  features:
    imageCache:
      localEnabled: true
```

Without this config, Talos automatically removes the IMAGECACHE partition. See `runbooks/talos-image-cache.md` for the full procedure.

### Template Creation

Create PVE templates from Talos factory images. See `runbooks/talos-template-create.md`.

Key differences from generic templates:
- Image format is `.raw.xz` (not qcow2) -- decompress with `xz -d` before import
- No cloud-init drive -- Talos configures itself via `talosctl apply-config`
- UEFI boot required (`bios: ovmf`)
- Tag with `template;talos` for identification

### Cluster Bootstrap

Full Talos bootstrap from provisioned VMs to healthy Kubernetes cluster. See `runbooks/talos-cluster-bootstrap.md`.

Workflow summary:
1. Generate secrets (`talosctl gen secrets`) -- one-time, store securely
2. Generate base machine configs (`talosctl gen config`) with factory installer image
3. Create per-node patches for static IPs, hostnames, and VIP
4. Apply configs to all nodes (`talosctl apply-config --insecure`)
5. Bootstrap etcd on first CP node (`talosctl bootstrap`) -- **one node only**
6. Retrieve kubeconfig (`talosctl kubeconfig`)
7. Verify health (`talosctl health`, `kubectl get nodes`)

### Upgrade Procedures

Rolling upgrades for Talos OS and Kubernetes. See `runbooks/talos-upgrade.md`.

**Kubernetes upgrade:** `talosctl upgrade-k8s --to <version>` -- targets one CP node, orchestrates the entire cluster.

**Talos OS upgrade:** `talosctl upgrade --image <factory-installer> --preserve` -- one node at a time, verify health between each.

**Order:** Always upgrade Kubernetes first, then Talos OS.

### Day-2 Operations

**etcd backups:** See `runbooks/talos-etcd-backup.md`. Take snapshots before upgrades and on a regular schedule. Store off-cluster.

**Certificate rotation:** Talos handles internal certificate rotation automatically. Cluster CA certificates have a 10-year lifetime by default.

**Node replacement:** To replace a failed node, provision a new VM from the template, apply the appropriate machine config (reusing the old node's patch with the new IP if needed), and let it join the cluster. Remove the old node from etcd membership if it cannot rejoin: `talosctl etcd remove-member --nodes <healthy_cp> <failed_member_id>`.

### talosctl Quick Reference

| Command | Purpose |
|---------|---------|
| `talosctl health` | Cluster health check (etcd, kubelet, API server, scheduler, controller-manager) |
| `talosctl get members` | List cluster members and their roles |
| `talosctl get disks --insecure --nodes <ip>` | Disk discovery on maintenance-mode nodes |
| `talosctl dashboard` | Live cluster dashboard (TUI) |
| `talosctl logs <service> --nodes <ip>` | Service logs (kubelet, etcd, apid, machined, etc.) |
| `talosctl services --nodes <ip>` | List running Talos services |
| `talosctl containers -k --nodes <ip>` | List Kubernetes containers on a node |
| `talosctl version --nodes <ip>` | Show Talos and Kubernetes versions |
| `talosctl get extensions --nodes <ip>` | List installed system extensions |
| `talosctl etcd members` | List etcd cluster members |
| `talosctl etcd snapshot <path> --nodes <ip>` | Create etcd snapshot |
| `talosctl apply-config --nodes <ip> --file <yaml>` | Apply or update machine config |
| `talosctl upgrade --nodes <ip> --image <ref>` | Upgrade Talos OS on a node |
| `talosctl upgrade-k8s --to <version>` | Upgrade Kubernetes version cluster-wide |

### Future: Cluster API (CAPI)

Declarative, GitOps-driven cluster provisioning is possible via Cluster API with Talos providers. This is not currently implemented but noted for future consideration.

Key architecture:
- Requires a management cluster running CAPI controllers
- Uses `cluster-api-provider-proxmox` (IONOS) for PVE VM provisioning
- Uses `cluster-api-bootstrap-provider-talos` and `cluster-api-control-plane-provider-talos` for Talos machine config management
- Template must use nocloud image (not bare-metal)
- Enables declarative cluster lifecycle managed through Kubernetes CRDs and reconciled by controllers

## Ansible Integration

For multi-node orchestration, delegate to existing Ansible playbooks in the fleet-infra repository. The repository path and inventory are defined in the `ansible` section of `cluster-config.yaml`. The skill does **not** modify Ansible playbooks or inventory files -- it is a consumer of existing automation, not an editor.

### General Delegation Pattern

Construct delegation commands using paths from `cluster-config.yaml`:

```bash
ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/<playbook>.yaml
```

Where `<FLEET_INFRA_PATH>` is `ansible.fleet_infra_path` and `<INVENTORY>` is `ansible.inventory` from `cluster-config.yaml`.

### Available Playbooks

| Playbook | Purpose | Tags |
|----------|---------|------|
| `talos-provision-vms.yaml` | Provision Talos VMs via Proxmox API (clone, configure, start) | `controlplane`, `workers` |
| `reboot-vms.yaml` | Rolling reboot of VMs by group | -- |
| `pve-servers.yaml` | Proxmox host configuration and maintenance | -- |
| `ping.yaml` | Connectivity check for all hosts in inventory | -- |

### Talos Cluster Provisioning via Ansible

For standard Talos cluster topologies that match the existing playbook, Ansible delegation is the preferred approach. The playbook handles VM cloning, configuration, and startup in a single run.

**Extract Proxmox API token for Ansible** (required as an environment variable):

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)"
```

**Full cluster provisioning (control plane + workers):**

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/talos-provision-vms.yaml
```

**Control plane only:**

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/talos-provision-vms.yaml \
  --tags controlplane
```

**Workers only:**

```bash
PROXMOX_API_TOKEN="$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/talos-provision-vms.yaml \
  --tags workers
```

### When to Use Ansible vs Direct API

| Use Ansible when... | Use direct API when... |
|----------------------|------------------------|
| The topology matches the existing playbook | The cluster profile has custom placement or sizing |
| You want a single command for the full lifecycle | You need step-by-step control with verification |
| The inventory already defines the target hosts | You're working with a new profile not in inventory |
| Rolling operations across many nodes (reboots, updates) | Single-VM operations (resize, snapshot, migrate) |

Ansible and cluster profiles serve complementary roles: Ansible playbooks encode a fixed workflow for a known topology, while cluster profiles are a declarative format that the skill interprets step-by-step via the API. For clusters defined in both, either approach works -- use Ansible for speed, direct API for flexibility.

### Fleet-Wide Operations

Target specific hosts or groups using `--limit`:

```bash
ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/<playbook>.yaml \
  --limit <PATTERN>
```

Common host patterns:

| Pattern | Matches |
|---------|---------|
| `controlplane` | All control plane nodes |
| `workers` | All worker nodes |
| `pve01` | Single Proxmox host |
| `pve*` | All Proxmox hosts |
| `k0s01,k0s02` | Specific nodes by name |
| `all:!workers` | Everything except workers |

## Host Configuration Automation

While the Ansible Integration section above covers **VM provisioning** playbooks, this section addresses **hypervisor host configuration** -- ensuring every Proxmox node has consistent network, repository, certificate, NTP, monitoring, and user management settings. This prevents configuration drift across large clusters.

### Architecture: Role-Based Desired State

Host configuration uses a modular Ansible role architecture where each configuration domain is an independent role. A top-level role list controls which domains are active:

```yaml
# defaults/main.yml -- toggle roles on/off
roles:
  - network
  - repositories
  - certificates
  - ntp
  - monitoring
  - notifications
  - certbot
  - usermgmt
```

Comment out a role to disable it. The main playbook dynamically includes enabled roles:

```yaml
---
- hosts: all
  gather_facts: true
  tasks:
    - name: Include roles
      include_vars: defaults/main.yml

    - name: Include {{ roles | length }} role(s)
      include_role:
        name: "{{ role.split('#')[0] }}"
        tasks_from: "{{ role.split('#')[1] | default('main') }}"
      with_items: "{{ roles }}"
      loop_control:
        loop_var: role
```

The `role.split('#')` pattern allows targeting specific task files within a role (e.g., `network#vlans` runs `roles/network/tasks/vlans.yml`).

### Configuration Domains

| Role | Purpose |
|------|---------|
| `network` | Bridge/interface configuration, VLAN-aware bridges, management + trunk interfaces |
| `repositories` | APT repository management (enterprise/no-subscription, Ceph) |
| `certificates` | SSL/TLS certificate deployment for Proxmox web UI |
| `ntp` | Time synchronization (chrony/systemd-timesyncd) |
| `monitoring` | Monitoring agent installation and configuration |
| `notifications` | Alert/notification channel setup |
| `certbot` | Let's Encrypt certificate automation |
| `usermgmt` | Host-level user/group/permission management |

### Network Configuration Pattern

The network role uses a data-driven approach with Jinja2 templating:

**Data definition** (`roles/network/defaults/main.yml`):

```yaml
networkfacts:
  - mgmt:
    type: mgmt
    bridge: vmbr0
    int: [ens192]
    intmode: manual
    bridgemode: static
    ipaddress: "192.168.100.10/24"
    gateway: "192.168.100.1"
  - trunk:
    bridge: vmbr1
    int: [ens224]
    type: trunk
    intmode: manual
    bridgemode: static
```

**Jinja2 template** (`roles/network/templates/networkconfig.j2`) generates `/etc/network/interfaces` from the data, handling management interfaces (with IP) and trunk interfaces (VLAN-aware bridges with `bridge-vids 2-4094`).

**Task** applies the template:

```yaml
- name: Create network resources
  template:
    src: "../templates/networkconfig.j2"
    dest: "/etc/network/interfaces"
```

### When to Use Host Configuration Automation

| Use host config automation when... | Use the Proxmox API when... |
|-------------------------------------|------------------------------|
| Onboarding new Proxmox nodes | Creating/managing VMs |
| Enforcing consistent network bridges across nodes | Configuring individual VM settings |
| Managing host-level certificates and repos | Cloning templates, migrating VMs |
| Recovering from host reinstallation | Cluster lifecycle (create/teardown) |
| Preventing configuration drift at scale | Single-node status checks |

### Reference

Full reference material with all code examples and implementation details is available in the knowledge base at `skills/knowledge-base/reference/proxmox-ansible-host-config/ansible-host-configuration.md`.

## Taskfile CLI

A `Taskfile.yml` in this skill directory wraps common Proxmox API operations as ergonomic one-liners using [go-task](https://taskfile.dev/). This is a convenience wrapper -- all operations can still be performed via raw API calls as documented above.

### Requirements

- `go-task` v3+
- `jq`
- `yq` (for cluster profile operations)
- `pass` (credentials are resolved at runtime via `$(pass show ...)` -- never stored in variables)

### Usage

Run from the skill directory (`skills/proxmox-manager/`):

```bash
# List all available tasks
task --list

# Verify API connectivity
task pve:check

# List all VMs
task pve:vms

# List templates
task pve:templates

# Show VM config
task pve:vm:config VMID=1031

# Start / stop a VM
task pve:vm:start VMID=1031
task pve:vm:stop VMID=1031

# Clone a template
task pve:vm:clone TEMPLATE=101 VMID=1040 NAME=test-vm

# Set VM configuration (any combination of CORES, MEMORY, TAGS, IP)
task pve:vm:set VMID=1031 CORES=4 MEMORY=8192 IP=10.0.0.31/24

# Migrate a VM
task pve:vm:migrate VMID=1031 TARGET=pve02

# Resize a disk
task pve:vm:resize VMID=1031 SIZE=+50G

# Cluster operations
task pve:cluster:list
task pve:cluster:status PROFILE=talos-staging
task pve:cluster:create PROFILE=talos-staging
task pve:cluster:teardown PROFILE=talos-staging
```

### Node Resolution

Most VM operations automatically resolve the node hosting a given VMID by querying `cluster/resources`. You only need to pass `VMID` -- not the node name.

### Clone Behavior

`pve:vm:clone` always clones to the same node as the template to avoid `can't clone to non-shared storage` errors. To place a VM on another node, clone first then migrate with `pve:vm:migrate`.

### Destructive Operations

Tasks that destroy data require interactive confirmation:
- `pve:vm:kill` -- force-stop
- `pve:vm:delete` -- permanent deletion (auto-stops running VMs first)
- `pve:cluster:teardown` -- destroys all VMs matching profile tags

## Troubleshooting

### API Returns 401
- Token may be expired or invalid
- Verify token exists: `pass ls <PASS_PATH>` (lists entry without showing content)
- Re-run bootstrap if needed

### API Returns 000
- Node may be down or unreachable
- Check network: `ping -c 1 <NODE_HOST>`
- Try another node -- most API calls work against any cluster member

### SSH Host Key Changed
- Common after node reinstall
- Fix: `ssh-keygen -R <NODE_HOST>` then reconnect to accept new key

### Permission Denied (403)
- The custom role may be missing a required privilege
- Check current role: `ssh <SSH_USER>@<NODE_HOST> 'pveum role list --output-format json' | jq '.[] | select(.roleid == "<ROLE_NAME>")'`
- Add missing privileges: `ssh <SSH_USER>@<NODE_HOST> 'pveum role modify <ROLE_NAME> --privs "existing+new"'`
