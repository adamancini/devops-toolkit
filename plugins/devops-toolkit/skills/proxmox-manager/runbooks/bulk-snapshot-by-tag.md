---
name: bulk-snapshot-by-tag
description: Create snapshots across all VMs matching a given tag
image_type: none
requires: [api]
tested_with:
  proxmox: "8.x"
---

# Bulk Snapshot by Tag

Create a snapshot on every VM that has a specific tag. Useful for pre-change snapshots of an entire cluster tier (e.g., snapshot all `k8s-worker` VMs before a Kubernetes upgrade).

## Parameters

- tag: Tag to filter VMs by (required)
- snap_name: Snapshot name -- alphanumeric, hyphens, underscores; no spaces (required)
- description: Human-readable snapshot description (default: "Bulk snapshot for tag <tag>")
- vmstate: Include RAM state -- `1` for live snapshot, `0` for disk-only (default: 0)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- Target VMs must be accessible via the API
- Sufficient storage space on each VM's storage backend for the snapshot

## Steps

1. **Verify API connectivity** (API)
   ```bash
   curl -sk -o /dev/null -w "%{http_code}" \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     https://<NODE_HOST>:8006/api2/json/version
   ```
   Expected result: `200`

2. **List VMs matching the tag** (API)
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.template != 1) | select(.tags // "" | split(";") | any(. == "<tag>")) | {vmid, name, status, node, tags}]'
   ```
   Expected result: JSON array of non-template VMs with the specified tag.

3. **Confirm with user** (no API call -- user interaction)

   Present the list of VMs that will receive a snapshot:

   | VMID | Name | Status | Node |
   |------|------|--------|------|
   | ...  | ...  | ...    | ...  |

   Confirm:
   - Snapshot name: `<snap_name>`
   - Description: `<description>`
   - VM state: `<vmstate>` (0 = disk-only, 1 = include RAM)
   - Number of VMs: N

   Wait for user approval before proceeding.

4. **Create snapshot on each VM** (API)

   For each VM in the list:
   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     -d "snapname=<snap_name>&description=<DESCRIPTION>&vmstate=<vmstate>" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<NODE>/qemu/<VMID>/snapshot"
   ```
   - URL-encode the description if it contains special characters
   - Each call returns a task UPID -- poll until complete before proceeding to the next VM
   - If a snapshot fails on one VM, log the error and continue with the remaining VMs

   Expected result: Task UPID for each VM that completes with `exitstatus == "OK"`.

5. **Verify all snapshots were created** (API)

   For each VM, confirm the snapshot exists:
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<NODE>/qemu/<VMID>/snapshot" \
     | jq '.data[] | select(.name == "<snap_name>") | {name, description, snaptime: (.snaptime | todate), vmstate}'
   ```
   Expected result: Snapshot with the expected name exists on every target VM.

6. **Report results**

   Present a summary table:

   | VMID | Name | Node | Snapshot | Result |
   |------|------|------|----------|--------|
   | ...  | ...  | ...  | ...      | OK/FAILED |

## Cleanup

- To roll back all snapshots: use the Snapshot Management rollback API on each VM (destructive -- confirm first)
- To delete all snapshots after the change is validated:
  ```bash
  # For each VM:
  curl -sk -X DELETE \
    -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
    "https://<NODE_HOST>:8006/api2/json/nodes/<NODE>/qemu/<VMID>/snapshot/<snap_name>"
  ```

## Notes

- Disk-only snapshots (`vmstate=0`) are near-instant on LVM-thin and have minimal performance impact
- RAM snapshots (`vmstate=1`) briefly pause the VM and take longer -- use only when you need to restore to exact running state
- Avoid leaving bulk snapshots in place for extended periods -- snapshot chains degrade I/O performance
- This procedure excludes templates (they are immutable and do not need snapshots)
- For VMs with the QEMU guest agent enabled, filesystem freeze/thaw is automatic during snapshot creation
