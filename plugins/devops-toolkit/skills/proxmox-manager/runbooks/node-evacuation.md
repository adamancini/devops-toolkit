---
name: node-evacuation
description: Evacuate all VMs from a node before maintenance by migrating them to other cluster members
image_type: none
requires: [api]
---

# Node Evacuation

Migrate all VMs off a source node to other cluster members before performing node maintenance (firmware updates, hardware replacement, storage expansion, etc.).

## Parameters

- source_node: Node to evacuate, e.g. `pve01` (required)
- dry_run: Preview the migration plan without executing (default: true)
- target_node: Specific destination node (optional -- if omitted, VMs are spread across all other online nodes)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- At least one other online node in the cluster with sufficient resources
- Source node must be accessible via the API (online)
- VMs using local storage will be migrated with storage migration (disk data copied over network)

## Steps

1. **Verify API connectivity** (API)
   ```bash
   curl -sk -o /dev/null -w "%{http_code}" \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     https://<NODE_HOST>:8006/api2/json/version
   ```
   Expected result: `200`

2. **Inventory VMs on the source node** (API)
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.node == "<source_node>" and .template != 1) | {vmid, name, status, maxcpu: .maxcpu, maxmem: (.maxmem / 1073741824 | floor | tostring + "G")}]'
   ```
   Expected result: JSON array of all non-template VMs on the source node with their resource requirements.

3. **Check available resources on target nodes** (API)

   For each candidate target node (all online nodes except the source):
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<TARGET_NODE>/status" \
     | jq '{node: "<TARGET_NODE>", cpu: .data.cpu, memory_free: ((.data.memory.total - .data.memory.used) / 1073741824 | floor | tostring + "G"), memory_total: (.data.memory.total / 1073741824 | floor | tostring + "G")}'
   ```
   Expected result: Free memory and CPU load for each candidate node.

4. **Plan VM placement** (no API call -- reasoning step)

   Distribute VMs across available nodes using a spread strategy:
   - Sort VMs by memory (largest first) for bin-packing efficiency
   - Assign each VM to the target node with the most available memory
   - Subtract the VM's memory from the target's available pool after each assignment
   - If a specific `target_node` was provided, assign all VMs there (verify capacity first)

   Present the plan to the user as a table:

   | VMID | Name | Status | Memory | Target Node |
   |------|------|--------|--------|-------------|
   | ...  | ...  | ...    | ...    | ...         |

   **If `dry_run` is true (default), stop here.** Display the plan and wait for the user to confirm or adjust.

5. **Shut down running VMs that cannot be live-migrated** (API)

   If any VMs use local storage without live migration support, shut them down first:
   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<source_node>/qemu/<VMID>/status/shutdown"
   ```
   Wait for graceful shutdown by polling VM status until `status == "stopped"`. For VMs that are already stopped, skip this step.

6. **Migrate each VM to its assigned target** (API)

   For each VM in the plan, execute the migration:
   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     -d "target=<TARGET_NODE>&online=1" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<source_node>/qemu/<VMID>/migrate"
   ```
   - Use `online=1` for running VMs (live migration)
   - Use `online=0` for stopped VMs (offline migration)
   - Migrate sequentially -- wait for each migration task to complete before starting the next
   - Poll the returned UPID until `status == "stopped"` and `exitstatus == "OK"`
   - If a migration fails, report the error and continue with the remaining VMs

   Expected result: Each migration returns a task UPID that completes successfully.

7. **Verify evacuation is complete** (API)
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.node == "<source_node>" and .template != 1)]'
   ```
   Expected result: Empty array `[]` -- no non-template VMs remain on the source node.

8. **Report results**

   Present a summary table:

   | VMID | Name | Status | Source | Target | Result |
   |------|------|--------|--------|--------|--------|
   | ...  | ...  | ...    | ...    | ...    | OK/FAILED |

## Cleanup

- No cleanup required -- VMs are migrated, not copied
- Templates remain on the source node (they are not migrated)
- After node maintenance is complete, VMs can be migrated back if desired

## Notes

- Live migration (`online=1`) keeps VMs running with minimal downtime (typically <1s for VMs with moderate memory dirty rates)
- VMs with large memory footprints or high dirty rates may take longer to converge -- Proxmox will automatically switch to post-copy migration if needed
- Sequential migration avoids network bandwidth contention between parallel migrations
- If the source node becomes unreachable during evacuation, remaining VMs cannot be migrated -- they must be recovered through HA fencing or manual intervention
- Templates are excluded from evacuation because they are immutable and have no running state
