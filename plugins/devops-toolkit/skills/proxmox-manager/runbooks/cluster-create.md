---
name: cluster-create
description: Provision an entire cluster from a cluster profile, including VM creation, Talos bootstrap, and Flux CD setup
image_type: none
requires: [api, ssh, talosctl, flux]
tested_with:
  proxmox: "8.x"
---

# Cluster Create

## Parameters

- profile: Path to the cluster profile YAML file (required)
- dry_run: Print the creation plan without executing (default: true)
- skip_talos: Skip Talos bootstrap steps 11-13 (default: false)
- skip_flux: Skip Flux bootstrap step 14 (default: false)

## Prerequisites

- API credentials configured in `pass` (see RBAC Bootstrap)
- Template VMID from the profile must exist in the cluster
- `talosctl` CLI installed (required unless `skip_talos: true`)
- `flux` CLI installed (required unless `skip_flux: true`)
- Network connectivity to the Proxmox API and to the VMs once started

## Steps

1. **Read the cluster profile** (local)

   Parse the profile YAML and extract all fields: node assignments, template VMID, tags, network config, Talos version, and Flux settings.

   ```bash
   yq '.' skills/proxmox-manager/clusters/<PROFILE_NAME>.yaml
   ```

   Validate required fields: `name`, `type`, `template`, `tags`, `nodes.controlplane`.

2. **Verify API connectivity** (API)

   ```bash
   curl -sk -o /dev/null -w "%{http_code}" \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     https://<NODE_HOST>:8006/api2/json/version
   ```

   Expected: `200`. Abort if not reachable.

3. **Verify template exists** (API)

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '.data[] | select(.vmid == <TEMPLATE_VMID>) | {vmid, name, node, template}'
   ```

   Expected: Returns the template entry with `template: 1`. Note which node the template resides on -- clones must originate from that node (Proxmox clones from the source node).

4. **Check for existing cluster VMs** (API)

   Query for VMs already matching the profile's tags to detect conflicts:

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[] | select(.template != 1) | select((.tags // "" | split(";")) as $t | ("<TAG1>" | IN($t[])) and ("<TAG2>" | IN($t[]))) | {vmid, name, status, node}]'
   ```

   If VMs are found, warn the user. Abort unless they confirm overwrite (which means running cluster-teardown first).

5. **Allocate VMIDs** (local)

   If the profile has explicit `assignments` with VMIDs, use those. Otherwise, auto-allocate from `start_vmid`:

   ```bash
   # Get all existing VMIDs
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[].vmid] | sort'
   ```

   For each node in the profile, verify the target VMID is not in the existing list. Abort on collision.

6. **Present creation plan** (local)

   Display a summary table of what will be created:

   | Name | VMID | Node | Cores | Memory | Disk | IP | Role |
   |------|------|------|-------|--------|------|----|------|
   | k0s01 | 1031 | pve01 | 4 | 8192MB | 100G | 10.0.0.31 | controlplane |
   | k0s02 | 1032 | pve02 | 4 | 8192MB | 100G | 10.0.0.32 | controlplane |
   | ... | ... | ... | ... | ... | ... | ... | ... |

   If `dry_run: true`, stop here and report the plan.

7. **Clone VMs from template** (API)

   For each node assignment, clone the template. Clones targeting different Proxmox nodes can run in parallel:

   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     -d "newid=<VMID>&name=<VM_NAME>&full=1&target=<TARGET_NODE>&storage=<STORAGE>" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<TEMPLATE_NODE>/qemu/<TEMPLATE_VMID>/clone"
   ```

   Each clone returns a task UPID. Poll all tasks until `status == "stopped"` and `exitstatus == "OK"`.

   **Parallelism note:** When cloning to different target nodes, Proxmox can process clones concurrently. When cloning multiple VMs to the same node, they are serialized by the storage backend. Issue all clone requests, then poll all UPIDs.

8. **Configure each VM** (API)

   Apply CPU, memory, tags, and disk resize to each cloned VM:

   ```bash
   # Set CPU, memory, and tags
   curl -sk -X PUT \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     -d "cores=<CORES>&memory=<MEMORY>&tags=<TAGS_SEMICOLON_SEPARATED>" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/config"
   ```

   Tags should include all profile tags plus the role tag (e.g., `talos;kubernetes;staging;controlplane`).

   ```bash
   # Resize disk if needed (only if profile disk size > template disk size)
   curl -sk -X PUT \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     -d "disk=scsi0&size=<DISK_SIZE>" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/resize"
   ```

9. **Start all VMs** (API)

   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<TARGET_NODE>.<CLUSTER_DOMAIN>:8006/api2/json/nodes/<TARGET_NODE>/qemu/<VMID>/status/start"
   ```

   Issue start commands for all VMs, then poll task UPIDs until all are running.

10. **Wait for VMs to be reachable** (local)

    For Talos nodes, wait for the Talos API port:

    ```bash
    # Wait for Talos API (port 50000) on each node
    for ip in <IP1> <IP2> <IP3>; do
      echo "Waiting for $ip:50000..."
      until nc -z -w 2 "$ip" 50000 2>/dev/null; do
        sleep 5
      done
      echo "$ip is reachable"
    done
    ```

    For generic clusters, wait for SSH (port 22):

    ```bash
    for ip in <IP1> <IP2> <IP3>; do
      echo "Waiting for $ip:22..."
      until nc -z -w 2 "$ip" 22 2>/dev/null; do
        sleep 5
      done
      echo "$ip is reachable"
    done
    ```

    Timeout after 5 minutes per node. If a node is unreachable, report the failure and abort.

11. **Generate Talos machine configs** (local -- skip if `skip_talos: true`)

    ```bash
    talosctl gen config <CLUSTER_NAME> https://<API_ENDPOINT>:6443 \
      --output-dir <CONFIG_DIR> \
      --with-cluster-discovery=false \
      --kubernetes-version <K8S_VERSION> \
      --config-patch '[{"op": "add", "path": "/cluster/network/podSubnets", "value": ["<POD_CIDR>"]},
                       {"op": "add", "path": "/cluster/network/serviceSubnets", "value": ["<SERVICE_CIDR>"]}]'
    ```

    This generates `controlplane.yaml`, `worker.yaml`, and `talosconfig` in the config directory.

12. **Apply Talos configs to each node** (local -- skip if `skip_talos: true`)

    ```bash
    # Apply controlplane config to each control plane node
    for ip in <CP_IP1> <CP_IP2> <CP_IP3>; do
      echo "Applying controlplane config to $ip..."
      talosctl apply-config --insecure \
        --nodes "$ip" \
        --file <CONFIG_DIR>/controlplane.yaml
    done

    # Apply worker config to each worker node (if any)
    for ip in <WORKER_IPS>; do
      echo "Applying worker config to $ip..."
      talosctl apply-config --insecure \
        --nodes "$ip" \
        --file <CONFIG_DIR>/worker.yaml
    done
    ```

    Wait for nodes to reboot and rejoin (Talos applies config and reboots automatically).

13. **Bootstrap Kubernetes** (local -- skip if `skip_talos: true`)

    Bootstrap etcd on the first control plane node:

    ```bash
    talosctl bootstrap \
      --nodes <FIRST_CP_IP> \
      --talosconfig <CONFIG_DIR>/talosconfig \
      --endpoints <FIRST_CP_IP>
    ```

    Wait for the Kubernetes API to become available, then retrieve the kubeconfig:

    ```bash
    talosctl kubeconfig \
      --nodes <FIRST_CP_IP> \
      --talosconfig <CONFIG_DIR>/talosconfig \
      --endpoints <FIRST_CP_IP> \
      --force
    ```

    Verify the cluster is healthy:

    ```bash
    kubectl get nodes
    ```

    Expected: All control plane nodes in `Ready` state.

14. **Bootstrap Flux CD** (local -- skip if `skip_flux: true`)

    ```bash
    flux bootstrap github \
      --owner=<GITHUB_OWNER> \
      --repository=<REPO_NAME> \
      --path=<FLUX_PATH> \
      --branch=<FLUX_BRANCH> \
      --personal
    ```

    Extract `owner` and `repository` from the profile's `flux.repo` field. The `--path` comes from `flux.path` and `--branch` from `flux.branch`.

    Verify Flux is reconciling:

    ```bash
    flux get kustomizations
    ```

    Expected: Kustomizations show `Ready` status.

15. **Report results** (local)

    Display a summary table of the created cluster:

    | Name | VMID | Node | Status | IP | Role |
    |------|------|------|--------|----|------|
    | k0s01 | 1031 | pve01 | running | 10.0.0.31 | controlplane |
    | k0s02 | 1032 | pve02 | running | 10.0.0.32 | controlplane |
    | k0s03 | 1033 | pve03 | running | 10.0.0.33 | controlplane |

    Report bootstrap status:
    - Talos: bootstrapped / skipped
    - Flux: reconciling / skipped
    - Kubeconfig: merged into default context

## Cleanup

- Remove any temporary files created during config generation (if using a temp directory)
- If the create fails partway through, the partially created VMs remain. Run `cluster-teardown.md` to clean up before retrying

## Notes

- The `dry_run` parameter defaults to `true` as a safety measure. Always review the plan before executing.
- Clone operations are the slowest step. For a 100G template on local-lvm, expect 2-5 minutes per clone depending on I/O load.
- Talos bootstrap (steps 11-13) is idempotent -- if it fails partway through, re-running the same steps is safe.
- Flux bootstrap is also idempotent -- it will reconcile to the desired state regardless of prior state.
- For clusters with workers, bootstrap control plane nodes first, then workers, to ensure the API server is available when workers join.
