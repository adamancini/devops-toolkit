# Core API Operations Reference

This reference provides concrete API endpoints and examples for common Proxmox VE operations. All examples use placeholders from `cluster-config.yaml`:
- `<PASS_PATH>` -- `credentials.pass_path`
- `<NODE_HOST>` -- any `cluster.nodes[].host`
- `<CLUSTER_DOMAIN>` -- the domain suffix from `cluster.nodes[].host`
- `<SSH_USER>` -- `credentials.ssh_user`

## Cluster & Node Status

**Cluster health and node membership:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/status" \
  | jq '.data[] | {name, type, online}'
```

**Per-node resource usage:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/status" \
  | jq '{cpu: .data.cpu, memory_used: .data.memory.used, memory_total: .data.memory.total, uptime: .data.uptime}'
```

## VM Status & Listing

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
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.status == "running") | {vmid, name, node}]'
```

**List templates:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
  | jq '[.data[] | select(.template == 1) | {vmid, name, node}]'
```

Templates can also be identified by tag (see `tags.templates` in `cluster-config.yaml`), or by VMID range.

## VM Creation from Template (Clone)

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

## VM Start / Stop / Shutdown / Reboot

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

Requires the QEMU guest agent or ACPI support in the guest OS. The VM may take time to shut down gracefully.

**Stop (immediate -- use with caution):**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/stop"
```

Equivalent to pulling the power cord. May cause data loss. Prefer `shutdown` unless the VM is unresponsive.

**Reboot:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/status/reboot"
```

## VM Deletion

```bash
curl -sk -X DELETE \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>?purge=1&destroy-unreferenced-disks=1"
```

- `purge=1` -- remove from backup jobs, replication, and HA configuration
- `destroy-unreferenced-disks=1` -- delete orphaned disk images

**IMPORTANT:** Destructive and irreversible. Before executing: confirm VMID/name with user, verify VM is stopped, never delete templates without explicit confirmation.

## VM Resize

**CPU and memory (config change):**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "cores=<CORES>&memory=<MEM_MB>" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/config"
```

In practice, stop the VM before resizing CPU or memory.

**Disk resize (grow only):**

```bash
curl -sk -X PUT \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "disk=scsi0&size=+10G" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/qemu/<VMID>/resize"
```

- Prefix `size` with `+` to grow by that amount, or specify absolute (e.g., `50G`)
- Disks can only be grown, never shrunk
- Hot-resize is supported while the VM is running
- The guest OS must expand its filesystem to use the new space

## Task Polling

Many operations return a task UPID rather than completing synchronously. **Always poll with a timeout.**

**Single-shot status check:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/tasks/<UPID>/status" \
  | jq '{status: .data.status, exitstatus: .data.exitstatus}'
```

- `status == "running"` -- task in progress
- `status == "stopped"` and `exitstatus == "OK"` -- success
- `status == "stopped"` and `exitstatus != "OK"` -- failure

**Polling loop with timeout:**

```bash
poll_task() {
  local node="$1" upid="$2" timeout="${3:-120}" interval="${4:-5}"
  local elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    STATUS=$(curl -sk \
      -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
      "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/tasks/$upid/status" \
      | jq -r '.data.status')
    if [ "$STATUS" = "stopped" ]; then
      EXIT=$(curl -sk \
        -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
        "https://$node.<CLUSTER_DOMAIN>:8006/api2/json/nodes/$node/tasks/$upid/status" \
        | jq -r '.data.exitstatus')
      if [ "$EXIT" = "OK" ]; then
        echo "Task completed successfully"
        return 0
      else
        echo "Task failed: $EXIT"
        return 1
      fi
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  echo "Task timed out after ${timeout}s (UPID: $upid)"
  return 2
}
```

Usage: `poll_task pve01 "UPID:pve01:..." 300 10`

**Read task logs for debugging:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<NODE_NAME>/tasks/<UPID>/log?limit=50" \
  | jq '.data[] | .t'
```

**When tasks hang:**
- Check disk lock: `ssh <SSH_USER>@<NODE_HOST> 'qm unlock <VMID>'`
- Check pending snapshot merges: `ssh <SSH_USER>@<NODE_HOST> 'qm listsnapshot <VMID>'`
- Check backup job lock: `ssh <SSH_USER>@<NODE_HOST> 'cat /run/lock/qemu-server/lock-<VMID>.conf'`
- Check if task process is alive: extract PID from UPID, `ssh <SSH_USER>@<NODE_HOST> 'ps -p <PID>'`

## Migration

**Live migrate a running VM:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "target=<TARGET_NODE>&online=1" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<SOURCE_NODE>/qemu/<VMID>/migrate"
```

**Offline migrate a stopped VM:**

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "target=<TARGET_NODE>&online=0" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<SOURCE_NODE>/qemu/<VMID>/migrate"
```

Use offline migration when the VM is stopped, uses local storage, or you need to move between storage backends.

**Pre-migration resource check:**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/nodes/<TARGET_NODE>/status" \
  | jq '{cpu: .data.cpu, memory_free: ((.data.memory.total - .data.memory.used) / 1073741824 | floor | tostring + "G"), memory_total: (.data.memory.total / 1073741824 | floor | tostring + "G")}'
```

**Notes:**
- Live migration requires shared storage or local-to-local migration support (PVE 7.2+)
- With `local-lvm`, Proxmox copies disk data over the network automatically
- For VMs with large memory, consider `bwlimit` parameter (KiB/s)
