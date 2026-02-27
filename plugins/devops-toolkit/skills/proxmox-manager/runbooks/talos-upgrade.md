---
name: talos-upgrade
description: Upgrade Talos OS and Kubernetes versions with rolling, node-by-node procedures
image_type: none
requires: [talosctl, kubectl]
tested_with:
  talos: "1.9.x"
  kubernetes: "1.32.x"
  proxmox: "8.x"
---

# Talos OS and Kubernetes Upgrades

## Parameters

- profile: Cluster profile name (required -- reads version targets and factory config)
- target_talos_version: New Talos version to upgrade to (required for OS upgrade)
- target_k8s_version: New Kubernetes version to upgrade to (required for K8s upgrade)
- upgrade_type: "k8s" for Kubernetes only, "os" for Talos OS only, "both" for sequential (required)

## Prerequisites

- `talosctl` CLI installed (version matching or newer than `target_talos_version`)
- `kubectl` installed
- Cluster is healthy (`talosctl health` passes)
- Cluster profile has `talos.factory.schematic_id` set (for OS upgrades)
- etcd backup taken (see `talos-etcd-backup.md`)

## Steps

### Pre-Upgrade Checks

1. **Verify current cluster health** (local)

   ```bash
   talosctl health
   kubectl get nodes -o wide
   ```

   Expected result: All nodes healthy and Ready. Do not proceed if any node is NotReady or any health check fails.

2. **Check current versions** (local)

   ```bash
   # Talos OS version
   talosctl version --nodes <CP_IP1>

   # Kubernetes version
   kubectl version --short
   ```

   Record current versions for rollback reference.

3. **Take etcd backup** (local)

   ```bash
   talosctl etcd snapshot <config_dir>/etcd-pre-upgrade-$(date +%Y%m%d).snapshot \
     --nodes <CP_IP1>
   ```

   Expected result: Snapshot file created. Store off-cluster.

### Kubernetes Upgrade

4. **Upgrade Kubernetes** (local -- skip if `upgrade_type: os`)

   ```bash
   talosctl upgrade-k8s \
     --to <target_k8s_version> \
     --nodes <CP_IP1> \
     --endpoints <CP_IP1>
   ```

   This command targets a single control plane node but orchestrates the upgrade across the entire cluster. It upgrades:
   - API server, controller-manager, scheduler (on all CP nodes)
   - kube-proxy, CoreDNS
   - kubelet (on all nodes)

   Expected result: `talosctl upgrade-k8s` reports success. The process is rolling -- each component is upgraded one at a time.

5. **Verify Kubernetes upgrade** (local)

   ```bash
   kubectl version --short
   kubectl get nodes -o wide
   talosctl health
   ```

   Expected result: All nodes report the new Kubernetes version. All nodes Ready.

### Talos OS Upgrade

6. **Build the new installer image reference** (local -- skip if `upgrade_type: k8s`)

   Use the existing schematic ID from the cluster profile (same extensions):

   ```
   INSTALLER=factory.talos.dev/installer/<SCHEMATIC_ID>:v<target_talos_version>
   ```

   If extensions need to change, generate a new schematic first (see `talos-image-factory.md`).

7. **Upgrade control plane nodes one at a time** (local)

   For each control plane node, in sequence:

   ```bash
   echo "Upgrading <node_name> (<node_ip>)..."
   talosctl upgrade \
     --nodes <node_ip> \
     --image "$INSTALLER" \
     --preserve
   ```

   The `--preserve` flag keeps the node's ephemeral data (pod logs, etc.) across the upgrade. Talos uses an A/B partition scheme: the new version is written to the inactive partition, then the node reboots into it.

   **Wait for the node to rejoin after each upgrade:**

   ```bash
   echo "Waiting for <node_name> to rejoin..."
   until talosctl --nodes <node_ip> --endpoints <node_ip> version >/dev/null 2>&1; do
     sleep 10
   done
   echo "<node_name> is back"

   # Verify node health
   talosctl health --wait-timeout 5m
   kubectl get nodes
   ```

   Expected result: Node reboots, comes back with the new Talos version, and rejoins the cluster as Ready.

   **CRITICAL:** Wait for full cluster health before proceeding to the next node. Do not upgrade multiple control plane nodes simultaneously -- this risks losing etcd quorum.

8. **Upgrade worker nodes** (local -- skip if no workers)

   Workers can be upgraded in parallel (or sequentially for safety). For each worker:

   ```bash
   talosctl upgrade \
     --nodes <worker_ip> \
     --image "$INSTALLER" \
     --preserve
   ```

   Wait for the node to rejoin and verify workloads are rescheduled.

9. **Verify Talos OS upgrade** (local)

   ```bash
   # Check all nodes report the new version
   talosctl version --nodes <CP_IP1>,<CP_IP2>,<CP_IP3>

   # Full health check
   talosctl health
   kubectl get nodes -o wide
   ```

   Expected result: All nodes report `v<target_talos_version>` for the Talos OS version. All nodes Ready.

### Post-Upgrade

10. **Update cluster profile** (local)

    Update the profile YAML with new versions:

    ```yaml
    talos:
      version: "<target_talos_version>"
      kubernetes_version: "<target_k8s_version>"
    ```

    Commit the profile change to version control.

11. **Update talosctl client** (local)

    Ensure the local `talosctl` binary matches the cluster version:

    ```bash
    talosctl version --client
    ```

    If the client version is older than the cluster, update it. The client is backward-compatible with older clusters but forward-compatibility is not guaranteed.

## Cleanup

- Remove pre-upgrade etcd snapshot after confirming the upgrade is stable (or retain per your backup policy)
- No other cleanup needed -- Talos handles partition management automatically

## Lessons Learned (Production Incidents)

### Extension changes can rename network interfaces

Adding or removing Talos extensions changes the factory schematic, which changes the
initramfs and module loading order. This can cause virtio network device enumeration to
change (e.g., `eth0` becomes `ens18`). When this happens:

- Nodes reboot with DHCP addresses instead of their configured static IPs
- etcd peer URLs point to stale DHCP addresses, breaking quorum
- `talosctl patch` adds a second interface entry (strategic merge) instead of replacing
  the old one, resulting in duplicate configs with no default route
- Cilium BPF state gets corrupted when the interface name changes under it

**Prevention:** Before upgrading with a new schematic, check if the interface name
changed by booting one test node and running `talosctl get addresses`. If the interface
renamed, update ALL per-node patches and the Ansible template BEFORE upgrading remaining
nodes. The fleet-infra template is at `playbooks/templates/talos-node-patch.yaml.j2`.

### etcd peer URLs survive IP changes

After a node gets a DHCP address and then recovers its static IP, etcd still advertises
the old DHCP address as its peer URL. Other members cannot reach it. The fix is to reboot
the node (etcd does not support restart via `talosctl service etcd restart`).

### Verify outbound connectivity after rolling upgrades

After upgrading all nodes, verify pods can reach external registries before considering
the upgrade complete. Cilium BPF maps can become stale after interface renames, breaking
pod egress. Signs: CoreDNS in ImagePullBackOff, Flux source-controller cannot fetch git
repos, "network is unreachable" for HTTPS connections to external IPs. Fix: reboot all
nodes cleanly (rolling) to rebuild Cilium state from scratch.

### Proxmox VM destroy is asynchronous

The Proxmox API returns a UPID for stop and destroy operations, but the Ansible
`proxmox_kvm` module may check for VM existence before the destroy task completes.
This causes "ALREADY EXISTS" during clone when the VM is actually being destroyed.
Always wait and verify VMs are fully gone before re-provisioning. Check all PVE nodes
for the VMID, not just the expected target node -- VMs may be on the template source
node (pve01) if migration hadn't completed.

## Notes

- **Upgrade order:** Always upgrade Kubernetes first, then Talos OS. The Kubernetes upgrade is independent of the OS version, but upgrading Talos OS may change the kubelet version, which could conflict with an older API server.
- **A/B partition scheme:** Talos maintains two OS partitions. On upgrade, the new version is written to the inactive partition. If the upgrade fails to boot, the node automatically falls back to the previous partition on the next reboot.
- **Rollback:** To roll back a Talos OS upgrade, run `talosctl upgrade` with the previous version's installer image. Talos will write the old version to the now-inactive partition and reboot.
- **Schematic reuse:** If your extensions haven't changed, reuse the same schematic ID. The factory caches schematics permanently. Only generate a new schematic if you need different extensions.
- **Extension changes require full reprovisioning:** If you change the extension set (new schematic), prefer destroying and reprovisioning VMs from a new template rather than in-place `talosctl upgrade`. In-place upgrades with extension changes can cause interface renames, broken network configs, and cascading failures.
- **Skip versions:** Talos supports upgrading across multiple minor versions (e.g., 1.7 -> 1.9), but it's recommended to review release notes for each skipped version to identify breaking changes.
- **Maintenance window:** Each node upgrade involves a reboot (30-60 seconds of downtime per node). With 3 CP nodes and rolling upgrades, the Kubernetes API stays available throughout via the VIP.
