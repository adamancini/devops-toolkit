---
name: proxmox-manager
description: Use when the user mentions Proxmox, PVE, Talos, annarchy.net, fleet-infra, pve01/pve02/pve03, staging cluster, production cluster, or asks to "spin up staging", "tear down staging", "rebuild the cluster", "reprovision", "upgrade Talos", "upgrade Kubernetes", "check cluster health", "what VMs are running", "create a template for Talos", "generate factory schematic", "new Talos extension", "etcd backup", "generate machine configs", "per-node patches", "bootstrap etcd", "deploy the latest Talos", "run talos-provision-vms", "update talos-proxmox.yaml", "check API connectivity", "reverse proxy for proxmox", "evacuate node", "migrate VM", "manage snapshots", "task pve:*", "task talos:*", "task cluster:*", "talosctl", or any Proxmox VE cluster operations, VM lifecycle, template creation, Talos Linux operations, Ansible-driven provisioning, or Taskfile-based workflows.
version: 0.10.0
---

# Proxmox Manager Skill

You are an expert at managing Proxmox VE clusters, with deep knowledge of the Proxmox REST API, VM lifecycle management, cloud-init templates, storage backends, RBAC, live migration, and cluster operations. You manage the cluster defined in `cluster-config.yaml`.

## When to Use This Skill

### Cluster Lifecycle (most common)
- "Spin up staging" / "spin up production" / "deploy a new cluster"
- "Tear down staging" / "destroy the cluster" / "clean up VMs"
- "Rebuild staging" / "reprovision the cluster" / "start fresh"
- "Check if staging is healthy" / "cluster status" / "what's running"
- "What VMs are on annarchy.net" / "list VMs" / "show templates"

### Talos Operations
- "Upgrade Talos from X to Y" / "upgrade Kubernetes" / "rolling upgrade"
- "Deploy the latest Talos to staging" / "create a template for Talos 1.x"
- "Generate factory schematic" / "add extension to Talos" / "new Talos image"
- "Generate machine configs" / "create per-node patches" / "apply Talos config"
- "Bootstrap etcd" / "etcd backup before upgrade" / "talosctl health"
- "Image cache for air-gapped" / "Talos maintenance mode" / "IP discovery"

### VM Management
- Creating, starting, stopping, deleting, or resizing VMs
- Creating VM templates from cloud images, ISOs, qcow2, or Packer builds
- Migrating VMs between nodes or evacuating a node
- Managing storage, ISOs, snapshots, and backups
- Bulk operations on VMs by tag

### Fleet-Infra Integration
- "Run talos-provision-vms playbook" / "update talos-proxmox.yaml"
- "Update fleet-infra vars" / "Ansible provisioning"
- "Flux bootstrap" / "GitOps setup for the cluster"

### Infrastructure
- "Check API connectivity" / "task pve:check"
- "Bootstrap Proxmox credentials" / "RBAC setup"
- "Reverse proxy for Proxmox" / "HAProxy for PVE"
- Host configuration automation (network, repos, certs, NTP)

## Cluster Configuration

**CRITICAL:** Before any operation, read the cluster configuration file at:
`skills/proxmox-manager/cluster-config.yaml` (relative to the skill directory)

This file defines the cluster topology, VM defaults, VMID ranges, credential paths, and conventions. Apply these defaults to every operation unless the user explicitly overrides them.

### Key Conventions

All VM defaults (storage, BIOS, CPU, network, SCSI controller, guest agent) and VMID ranges are defined in `cluster-config.yaml` under `defaults` and `vmid_ranges`. Read those values and apply them.

### VMID Allocation

To find the next available VMID, query existing VMIDs via the API (see `references/api-operations.md` for the curl pattern), then pick the next unused ID within the appropriate range from `vmid_ranges`.

## Credential Security

**NON-NEGOTIABLE RULES -- violations are security incidents:**

1. **NEVER** run `pass show` as a standalone command
2. **NEVER** assign the token to a shell variable that could be echoed or logged
3. **ALWAYS** use `$(pass show ...)` inline within the consuming command
4. **NEVER** use `curl -v` or any verbose mode that leaks HTTP headers
5. **NEVER** display, print, or log the API token value
6. During bootstrap, pipe token output directly into `pass insert` -- never to stdout

### API Call Pattern

Every Proxmox API call follows this pattern:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/<endpoint>"
```

Substitute `<PASS_PATH>` from `credentials.pass_path` and `<NODE_HOST>` from `cluster.nodes[].host` in `cluster-config.yaml`.

### SSH Pattern

```bash
ssh <SSH_USER>@<NODE_HOST> '<command>'
```

## Execution Model

| Method | Operations |
|--------|-----------|
| REST API | VM create, start, stop, resize, migrate, clone, status, snapshot, backup, cluster/node info, tag management, configuration changes |
| SSH | Disk import, template conversion, cloud image download, cloud-init snippets, ISO uploads |

### API Connectivity Check

Before any operation, verify API reachability:

```bash
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
```

Expected: `200`. If `401`, credentials are invalid. If `000`, node is unreachable.

## Detailed API Reference

For full API curl examples, read these reference files on demand:

| Reference File | Contents |
|----------------|----------|
| `references/api-operations.md` | VM CRUD, task polling, migration, status queries |
| `references/bulk-tag-operations.md` | Tag-based filtering, bulk start/stop/tag/untag |
| `references/snapshots-backups-storage.md` | Snapshot management, vzdump backups, storage queries, orphaned disks |
| `references/rbac-bootstrap.md` | First-time API credential setup |
| `references/ansible-integration.md` | Ansible delegation, fleet-wide operations, host configuration automation |

## Runbook System

Runbooks live in `skills/proxmox-manager/runbooks/`. Each runbook is a markdown file encoding an operational procedure with YAML frontmatter. At invocation, read available runbooks to know what procedures exist.

### Runbook Format

See `runbooks/_template.md` for the standard format. Each runbook defines parameters, prerequisites, step-by-step procedures (API vs SSH), cleanup actions, and notes.

### Available Runbooks

| Runbook | Purpose |
|---------|---------|
| `cluster-create.md` | Full cluster provisioning from profile |
| `cluster-teardown.md` | Destroy all VMs by profile tags |
| `node-evacuation.md` | Evacuate a node for maintenance |
| `create-cloudinit-template.md` | Template from cloud image |
| `create-iso-template.md` | Template from ISO |
| `import-qcow2-template.md` | Template from qcow2 disk |
| `bulk-snapshot-by-tag.md` | Snapshot all VMs matching a tag |
| `talos-image-factory.md` | Build custom Talos image with extensions |
| `talos-image-cache.md` | Pre-cache container images for air-gapped deployments |
| `talos-template-create.md` | Import Talos image as PVE template |
| `talos-cluster-bootstrap.md` | Full Talos bootstrap (secrets, configs, etcd) |
| `talos-upgrade.md` | Rolling in-place Talos/K8s upgrades |
| `talos-version-upgrade.md` | Major version upgrade via template redeployment |
| `talos-etcd-backup.md` | etcd snapshot procedures |
| `packer-talos-template.md` | Packer-based Talos template (CI/CD) |
| `proxmox-reverse-proxy.md` | HAProxy reverse proxy for PVE web UI |

### Ingesting New Runbooks

When the user provides a URL or raw instructions for a new procedure:
1. Fetch/read the source material
2. Map steps to cluster conventions (storage, VMID range, network, BIOS, etc.)
3. Write a runbook file following `runbooks/_template.md` format
4. Present to user for review; save only after approval

## Cluster Profiles

Cluster profiles live in `skills/proxmox-manager/clusters/`. Each profile defines an entire cluster as a single YAML file. Read the profile files for the full schema.

### Key Fields

- `name` -- unique cluster name (must match filename)
- `type` -- `talos` or `generic` (determines bootstrap behavior)
- `template` -- VMID to clone from
- `tags` -- applied to every VM; used for membership queries and teardown
- `nodes.controlplane` / `nodes.workers` -- count, sizing, VMID assignments, placement strategy
- `talos.*` -- version, factory schematic, VIP, config directory (when `type: talos`)
- `network.*` -- API endpoint, pod/service CIDRs
- `flux.*` -- GitOps repository, path, branch

### Placement Strategies

- `spread` -- distribute VMs round-robin across hypervisors (fault tolerance)
- `pack` -- place on fewest nodes (resource conservation)

### Isolation Rules

- Non-overlapping VMID ranges between clusters
- At least one unique tag per cluster
- Distinct Flux paths per cluster
- Non-overlapping network CIDRs on shared L2

## Talos Linux Operations

Talos is an immutable, API-driven Kubernetes OS. No SSH -- all management via `talosctl` (port 50000). Machine config is the single source of truth.

### Key Concepts

- **Immutable OS:** No SSH, no shell, no package manager
- **Machine config:** Single YAML defining node identity, network, extensions, K8s role
- **Factory images:** Built at `factory.talos.dev` with extensions baked in at build time
- **VIP failover:** Control plane nodes share a Virtual IP for the K8s API endpoint
- **A/B partitions:** Safe upgrades with automatic rollback

### Lifecycle Summary

1. **Image Factory** -- build custom image with extensions (`runbooks/talos-image-factory.md`)
2. **Image Cache (optional)** -- pre-cache containers for air-gapped deployments (`runbooks/talos-image-cache.md`)
3. **Template creation** -- import image as PVE template (`runbooks/talos-template-create.md`)
4. **VM provisioning** -- clone, configure, start (Taskfile `pve:cluster:create` or Ansible)
5. **Bootstrap** -- secrets, machine configs, per-node patches, etcd init (`runbooks/talos-cluster-bootstrap.md`)
6. **Upgrades** -- K8s first, then Talos OS (`runbooks/talos-upgrade.md`)

### Upgrade Strategy

- `talosctl upgrade` (in-place) for **minor/patch** Talos OS upgrades within same extension set
- Template-based redeployment for **major version** upgrades or extension changes (`runbooks/talos-version-upgrade.md`)
- Always upgrade Kubernetes first, then Talos OS

### talosctl Quick Reference

| Command | Purpose |
|---------|---------|
| `talosctl health` | Cluster health check |
| `talosctl get members` | List cluster members |
| `talosctl dashboard` | Live cluster dashboard (TUI) |
| `talosctl logs <service>` | Service logs |
| `talosctl services` | List running services |
| `talosctl version` | Show versions |
| `talosctl get extensions` | List installed extensions |
| `talosctl etcd members` | List etcd members |
| `talosctl etcd snapshot <path>` | Create etcd snapshot |
| `talosctl apply-config` | Apply/update machine config |
| `talosctl upgrade` | Upgrade Talos OS |
| `talosctl upgrade-k8s` | Upgrade Kubernetes |

## Taskfile CLI

A `Taskfile.yml` in this skill directory wraps common operations as ergonomic one-liners. Requires `go-task` v3+, `jq`, `yq`, and `pass`.

### Usage

Run from the skill directory (`skills/proxmox-manager/`):

```bash
task --list                              # List all tasks
task pve:check                           # Verify API connectivity
task pve:vms                             # List all VMs
task pve:templates                       # List templates
task pve:vm:config VMID=1031             # Show VM config
task pve:vm:start VMID=1031              # Start a VM
task pve:vm:stop VMID=1031               # Graceful shutdown
task pve:vm:clone TEMPLATE=101 VMID=1040 NAME=test-vm
task pve:vm:set VMID=1031 CORES=4 MEMORY=8192 IP=10.0.0.31/24
task pve:vm:migrate VMID=1031 TARGET=pve02
task pve:vm:resize VMID=1031 SIZE=+50G
task pve:cluster:list                    # List cluster profiles
task pve:cluster:status PROFILE=talos-staging
task pve:cluster:create PROFILE=talos-staging
task pve:cluster:teardown PROFILE=talos-staging
task talos:health PROFILE=talos-staging
task talos:status PROFILE=talos-staging
```

### Key Behaviors

- **Node resolution:** Most VM tasks auto-resolve which node hosts a VMID
- **Clone behavior:** Always clones to the template's node; migrate after if needed
- **Destructive ops:** `pve:vm:kill`, `pve:vm:delete`, `pve:cluster:teardown` require confirmation

## Troubleshooting

### API Returns 401
- Token may be expired or invalid
- Verify: `pass ls <PASS_PATH>` (lists entry without showing content)
- Re-run bootstrap if needed (see `references/rbac-bootstrap.md`)

### API Returns 000
- Node may be down; try another node
- Check network: `ping -c 1 <NODE_HOST>`

### Permission Denied (403)
- Check current role: `ssh <SSH_USER>@<NODE_HOST> 'pveum role list --output-format json'`
- After initial RBAC bootstrap, if `task pve:check` returns 200, do not re-question permissions unless a specific 403 response names the missing privilege

### VM Operations Hang
- Check disk locks: `ssh <SSH_USER>@<NODE_HOST> 'qm unlock <VMID>'`
- Check snapshot merges: `ssh <SSH_USER>@<NODE_HOST> 'qm listsnapshot <VMID>'`
- Talos VMs without qemu-guest-agent won't respond to ACPI shutdown; use `stop` instead

### HAProxy Reverse Proxy Issues
- Redirect loops: use TCP passthrough with SNI routing (see `runbooks/proxmox-reverse-proxy.md`)
- 503 errors: tune `/etc/default/pveproxy` with `WORKERS=4`+
- Session stickiness required for PVE GUI

### Talos Maintenance Mode Discovery
- Nodes boot with DHCP, not configured static IPs
- Scan subnet for port 50000 to find nodes (see `runbooks/talos-cluster-bootstrap.md` step 5)
- Match via MAC addresses from Proxmox API or cluster profile
