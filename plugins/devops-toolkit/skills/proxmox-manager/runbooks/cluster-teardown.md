---
name: cluster-teardown
description: Destroy all VMs belonging to a cluster profile
image_type: none
requires: [api]
---

# Cluster Teardown

## Parameters

- profile: Path to the cluster profile YAML file (required)
- dry_run: List VMs that would be destroyed without executing (default: true)
- force: Skip graceful shutdown and force-stop all VMs immediately (default: false)
- shutdown_timeout: Seconds to wait for graceful shutdown before force-stopping (default: 120)

## Prerequisites

- API credentials configured in `pass` (see RBAC Bootstrap)
- The cluster profile must exist and its tags must accurately identify the target VMs

## Steps

1. **Read the cluster profile** (local)

   Parse the profile YAML and extract the `tags` list and `name`:

   ```bash
   yq '.' skills/proxmox-manager/clusters/<PROFILE_NAME>.yaml
   ```

   The tags are used to identify all VMs belonging to this cluster.

2. **Verify API connectivity** (API)

   ```bash
   curl -sk -o /dev/null -w "%{http_code}" \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     https://<NODE_HOST>:8006/api2/json/version
   ```

   Expected: `200`. Abort if not reachable.

3. **List all VMs matching cluster tags** (API)

   Query for VMs matching ALL tags from the profile (AND logic), excluding templates:

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.template != 1) | select((.tags // "" | split(";")) as $t | ("<TAG1>" | IN($t[])) and ("<TAG2>" | IN($t[])) and ("<TAG3>" | IN($t[]))) | {vmid, name, status, node, tags}]'
   ```

   Replace `<TAG1>`, `<TAG2>`, `<TAG3>` with the profile's tags. If no VMs are found, report "no VMs to teardown" and exit.

4. **Confirm with user** (local)

   Display the list of VMs that will be destroyed:

   | VMID | Name | Status | Node |
   |------|------|--------|------|
   | 1031 | k0s01 | running | pve01 |
   | 1032 | k0s02 | running | pve02 |
   | 1033 | k0s03 | running | pve03 |

   **WARNING: This operation is destructive and irreversible. All listed VMs and their disks will be permanently deleted.**

   If `dry_run: true`, stop here and report the plan.

   Ask the user to confirm before proceeding.

5. **Shutdown running VMs** (API)

   For each VM with `status == "running"`, send a graceful shutdown:

   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/status/shutdown"
   ```

   Wait up to `shutdown_timeout` seconds for VMs to stop. Poll each VM's status:

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/status/current" \
     | jq '.data.status'
   ```

   If a VM is still running after the timeout (or if `force: true`), force-stop it:

   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/status/stop"
   ```

6. **Delete all VMs** (API)

   Once all VMs are stopped, delete each one with purge and disk cleanup:

   ```bash
   curl -sk -X DELETE \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>?purge=1&destroy-unreferenced-disks=1"
   ```

   Each deletion returns a task UPID. Poll all tasks until `status == "stopped"` and `exitstatus == "OK"`.

7. **Verify teardown complete** (API)

   Re-run the tag query from step 3. The result should be an empty array:

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.template != 1) | select((.tags // "" | split(";")) as $t | ("<TAG1>" | IN($t[])) and ("<TAG2>" | IN($t[])) and ("<TAG3>" | IN($t[]))) | {vmid, name}]'
   ```

   Expected: `[]`. If VMs remain, report them as failed deletions.

8. **Report results** (local)

   Display a summary:

   | VMID | Name | Result |
   |------|------|--------|
   | 1031 | k0s01 | deleted |
   | 1032 | k0s02 | deleted |
   | 1033 | k0s03 | deleted |

   Report total VMs deleted and any failures.

## Cleanup

- No additional cleanup required -- `purge=1&destroy-unreferenced-disks=1` handles disk and config removal
- If Flux was bootstrapped, its resources in the Git repository are not affected (only the running cluster is destroyed)
- Kubeconfig contexts for the destroyed cluster may remain in `~/.kube/config` -- remove manually if desired

## Notes

- The `dry_run` parameter defaults to `true` as a safety measure. Always review the VM list before executing.
- Teardown identifies VMs by tags, not by VMID. If a VM has been manually untagged, it will not be found by this procedure. Similarly, if unrelated VMs share the same tags, they will be included -- review the list carefully.
- For a cluster rebuild (teardown + create), run this runbook first, then `cluster-create.md` with the same profile.
- Templates are excluded from teardown by the `select(.template != 1)` filter. The template used to create the cluster is preserved.
