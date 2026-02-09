---
name: talos-cluster-bootstrap
description: Full Talos Linux cluster bootstrap with secrets, machine configs, per-node patches, VIP, and etcd initialization
image_type: none
requires: [talosctl, kubectl]
---

# Talos Cluster Bootstrap

This runbook covers the full Talos bootstrap procedure after VMs are provisioned and running. It replaces/extends steps 11-13 of `cluster-create.md` with detailed per-node patching, VIP configuration, and extension-aware image references.

## Parameters

- profile: Cluster profile name (required -- reads all config from the profile YAML)
- config_dir: Directory for generated configs (default: from profile `talos.config_dir`)
- secrets_file: Path to secrets.yaml relative to config_dir (default: from profile `talos.secrets_file`)
- regenerate_secrets: Whether to regenerate secrets.yaml (default: false -- only true for first-time setup)

## Prerequisites

- `talosctl` CLI installed (matching the target Talos version)
- `kubectl` installed
- VMs provisioned, started, and reachable on port 50000 (Talos API in maintenance mode)
- Cluster profile loaded with `talos.*` fields populated (version, factory.schematic_id, vip, patches_dir)
- Network connectivity from the workstation to all node IPs

## Steps

1. **Verify all nodes are reachable in maintenance mode** (local)

   ```bash
   for ip in <CP_IP1> <CP_IP2> <CP_IP3> <WORKER_IPS...>; do
     echo -n "$ip: "
     if nc -z -w 2 "$ip" 50000 2>/dev/null; then
       echo "reachable"
     else
       echo "UNREACHABLE"
     fi
   done
   ```

   Expected result: All nodes report "reachable". If any node is unreachable, verify the VM is running and has the correct IP via the PVE console.

2. **Generate cluster secrets** (local -- skip if `regenerate_secrets: false` and secrets file exists)

   ```bash
   mkdir -p <config_dir>
   talosctl gen secrets -o <config_dir>/<secrets_file>
   ```

   Expected result: `secrets.yaml` created in the config directory. This file contains cluster CA keys, etcd keys, and bootstrap tokens. **Store securely -- this is the root of trust for the entire cluster.**

   If secrets already exist and `regenerate_secrets: false`, skip this step. Reusing secrets enables non-destructive config regeneration.

3. **Generate base machine configs** (local)

   Build the installer image reference from the factory schematic:

   ```
   INSTALLER=factory.talos.dev/installer/<SCHEMATIC_ID>:v<TALOS_VERSION>
   ```

   Generate configs:

   ```bash
   talosctl gen config <CLUSTER_NAME> https://<API_ENDPOINT>:6443 \
     --output-dir <config_dir> \
     --with-secrets <config_dir>/<secrets_file> \
     --install-image "$INSTALLER" \
     --kubernetes-version <KUBERNETES_VERSION> \
     --with-cluster-discovery=false \
     --force \
     --config-patch '[
       {"op": "add", "path": "/cluster/network/podSubnets", "value": ["<POD_CIDR>"]},
       {"op": "add", "path": "/cluster/network/serviceSubnets", "value": ["<SERVICE_CIDR>"]}
     ]'
   ```

   Expected result: `controlplane.yaml`, `worker.yaml`, and `talosconfig` in the config directory. The `--force` flag overwrites existing files.

   Values come from the cluster profile:
   - `<CLUSTER_NAME>` = profile `name`
   - `<API_ENDPOINT>` = profile `network.api_endpoint`
   - `<SCHEMATIC_ID>` = profile `talos.factory.schematic_id`
   - `<TALOS_VERSION>` = profile `talos.version`
   - `<KUBERNETES_VERSION>` = profile `talos.kubernetes_version`
   - `<POD_CIDR>` = profile `network.pod_cidr`
   - `<SERVICE_CIDR>` = profile `network.service_cidr`

4. **Create per-node config patches** (local)

   Create a patches directory:

   ```bash
   mkdir -p <config_dir>/<patches_dir>
   ```

   **Control plane node patch template** (one per CP node):

   ```yaml
   # <config_dir>/<patches_dir>/<node_name>.yaml
   machine:
     network:
       hostname: <node_name>
       interfaces:
         - interface: <vip_interface>
           dhcp: false
           addresses:
             - <node_ip>/24
           routes:
             - network: 0.0.0.0/0
               gateway: <gateway>
           vip:
             ip: <vip_ip>
       nameservers:
         - 1.1.1.1
         - 8.8.8.8
   ```

   - `<vip_interface>` = profile `talos.vip.interface`
   - `<vip_ip>` = profile `talos.vip.ip` (same as `network.api_endpoint` for HA)
   - `<node_ip>` = the node's IP from `nodes.controlplane.assignments[].ip`
   - `<gateway>` = derive from the node IP (e.g., `10.0.0.1` for the `10.0.0.0/24` subnet)

   The VIP section makes the Kubernetes API endpoint float between control plane nodes. Only one node holds the VIP at a time; it fails over automatically if the active holder goes down.

   **Worker node patch template** (one per worker, if any):

   ```yaml
   # <config_dir>/<patches_dir>/<worker_name>.yaml
   machine:
     network:
       hostname: <worker_name>
       interfaces:
         - interface: eth0
           dhcp: false
           addresses:
             - <worker_ip>/24
           routes:
             - network: 0.0.0.0/0
               gateway: <gateway>
       nameservers:
         - 1.1.1.1
         - 8.8.8.8
   ```

   Workers do not have the `vip` block.

5. **Apply configs to control plane nodes** (local)

   For each control plane node, apply the base config with the node-specific patch:

   ```bash
   talosctl apply-config --insecure \
     --nodes <node_ip> \
     --file <config_dir>/controlplane.yaml \
     --config-patch @<config_dir>/<patches_dir>/<node_name>.yaml
   ```

   Expected result: Each node accepts the config and reboots. The `--insecure` flag is required for the first apply because the node does not yet have a trusted config.

   Apply to all CP nodes before proceeding. The nodes will reboot and come up with the applied configuration.

6. **Apply configs to worker nodes** (local -- skip if no workers)

   ```bash
   talosctl apply-config --insecure \
     --nodes <worker_ip> \
     --file <config_dir>/worker.yaml \
     --config-patch @<config_dir>/<patches_dir>/<worker_name>.yaml
   ```

7. **Wait for nodes to become ready** (local)

   After config application, nodes reboot and join the Talos cluster. Wait for the Talos API to become available on the configured endpoints:

   ```bash
   # Configure talosctl to use the generated talosconfig
   export TALOSCONFIG=<config_dir>/talosconfig

   # Wait for each node's Talos API
   for ip in <CP_IP1> <CP_IP2> <CP_IP3>; do
     echo -n "Waiting for $ip... "
     until talosctl --nodes "$ip" --endpoints "$ip" version >/dev/null 2>&1; do
       sleep 10
     done
     echo "ready"
   done
   ```

   Expected result: All nodes respond to `talosctl version`. This confirms the Talos API is up with the applied config (no longer in maintenance mode).

8. **Bootstrap etcd on the first control plane node** (local)

   ```bash
   talosctl bootstrap \
     --nodes <FIRST_CP_IP> \
     --endpoints <FIRST_CP_IP>
   ```

   **CRITICAL:** Run this on exactly ONE control plane node. Running bootstrap on multiple nodes will create split-brain etcd clusters. The remaining control plane nodes will join automatically.

   Expected result: etcd cluster initialized. This is the point of no return -- after bootstrap, the cluster has state.

9. **Wait for Kubernetes API** (local)

   ```bash
   echo "Waiting for Kubernetes API..."
   until talosctl --nodes <FIRST_CP_IP> --endpoints <FIRST_CP_IP> \
     health --wait-timeout 10m 2>/dev/null; do
     sleep 10
   done
   echo "Cluster healthy"
   ```

   Expected result: `talosctl health` reports all components healthy (etcd, kubelet, API server, scheduler, controller-manager).

10. **Retrieve kubeconfig** (local)

    ```bash
    talosctl kubeconfig \
      --nodes <FIRST_CP_IP> \
      --endpoints <FIRST_CP_IP> \
      --force
    ```

    Expected result: Kubeconfig merged into `~/.kube/config` with a context named after the cluster. The `--force` flag overwrites any existing context with the same name.

11. **Configure talosctl endpoints and nodes** (local)

    Update the talosconfig for ongoing management:

    ```bash
    talosctl config endpoints <CP_IP1> <CP_IP2> <CP_IP3>
    talosctl config nodes <CP_IP1> <CP_IP2> <CP_IP3> <WORKER_IPS...>
    ```

    Expected result: `talosctl` commands will target all cluster nodes by default without needing `--nodes` and `--endpoints` flags.

12. **Verify cluster health** (local)

    ```bash
    talosctl health
    kubectl get nodes -o wide
    talosctl get members
    ```

    Expected result:
    - `talosctl health` reports all checks passed
    - `kubectl get nodes` shows all nodes in `Ready` state
    - `talosctl get members` shows all nodes as cluster members

## Cleanup

- No temporary files are created during bootstrap
- If bootstrap fails partway, the procedure is safe to retry from step 5 (re-apply configs) or step 8 (re-bootstrap)
- For a completely fresh start, tear down the VMs and reprovision

## Notes

- **Secrets management:** The `secrets.yaml` file is the root of trust. Store it securely (e.g., in a Git-encrypted repo, SOPS, or Vault). Losing it means you cannot regenerate machine configs that are compatible with the existing cluster.
- **VIP failover:** The VIP (`talos.vip.ip`) provides a stable Kubernetes API endpoint. It floats between control plane nodes via Talos's built-in ARP-based failover. No external load balancer is needed.
- **Insecure flag:** `--insecure` is only needed for the first config application when nodes are in maintenance mode. Subsequent config changes should use the normal authenticated flow.
- **Config patches:** Patches use strategic merge patch format by default. JSON6902 patches are also supported via `--config-patch-control-plane` and `--config-patch-worker` flags on `talosctl gen config`. Per-node patches override values in the base `controlplane.yaml` or `worker.yaml`.
- **Idempotency:** Steps 5-6 (apply config) and step 8 (bootstrap) are safe to retry. `talosctl apply-config` is idempotent. `talosctl bootstrap` will fail harmlessly if etcd is already initialized.
- **Extension verification:** After bootstrap, verify extensions are loaded:
  ```bash
  talosctl get extensions --nodes <any_node_ip>
  ```
  Should list `qemu-guest-agent` and any other extensions baked into the image.
