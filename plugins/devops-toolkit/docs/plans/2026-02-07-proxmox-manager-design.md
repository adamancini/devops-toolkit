# Proxmox Manager -- Skill & Agent Design

## Overview

A Claude Code skill and agent for conversational management of a Proxmox VE cluster. Provides VM lifecycle management, template creation from any image type, node maintenance, migrations, bulk operations, backup/snapshot management, and full cluster lifecycle (spin up/tear down clusters as units). Uses a hybrid execution model: Proxmox REST API for structured operations, SSH for low-level disk and storage work. Stores operational knowledge as runbook files that can grow over time.

## Location

```
~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/
  skills/
    proxmox-manager/
      SKILL.md
      cluster-config.yaml
      runbooks/
        _template.md
        create-cloudinit-template.md
        create-iso-template.md
        import-qcow2-template.md
      clusters/
        talos-staging.yaml
  agents/
    proxmox-manager.md
```

Trigger phrases: "create a proxmox VM", "make a VM template", "migrate VM", "check proxmox status", "evacuate node", "manage proxmox snapshots", "import cloud image", "spin up a cluster", "tear down cluster", and similar.

## Cluster Configuration

The skill reads `cluster-config.yaml` at invocation to ground all operations in the user's environment:

```yaml
cluster:
  name: annarchy.net
  nodes:
    - name: pve01
      host: pve01.annarchy.net
    - name: pve02
      host: pve02.annarchy.net
    - name: pve03
      host: pve03.annarchy.net

defaults:
  storage: local-lvm
  network_bridge: vmbr0
  bios: ovmf
  machine: q35
  cpu: host
  scsi_controller: virtio-scsi-single
  efidisk_pre_enrolled_keys: false
  guest_agent: true

vmid_ranges:
  templates: 100-999
  vms: 1000-9999

credentials:
  pass_path: annarchy.net/pve/api-token
  ssh_user: root

tags:
  templates: ["template"]
  talos: ["talos", "kubernetes"]
  cloudinit: ["cloudinit"]

cloudinit:
  default_user: ada
  ssh_keys_source: ~/.ssh/authorized_keys
  vendor_snippet_path: /var/lib/vz/snippets/
```

The skill applies these defaults to every operation. Overrides are accepted per-operation. The config enables automatic VMID allocation by querying the API for the next unused ID within the appropriate range.

## RBAC & Service Account

A dedicated PVE-realm service account with least-privilege permissions.

- **Service account:** `claude-code@pve`
- **API token:** `claude-code@pve!automation`
- **Custom role:** `ClaudeCodeManager`

Bootstrap sequence (runs once via SSH as root):

```bash
# Create PVE-realm service account
pveum user add claude-code@pve

# Create custom role with scoped privileges
pveum role add ClaudeCodeManager --privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType \
   VM.PowerMgmt VM.Console VM.Monitor VM.Migrate VM.Snapshot VM.Snapshot.Rollback \
   VM.Backup VM.Audit \
   Datastore.Allocate Datastore.AllocateSpace Datastore.Audit \
   Sys.Audit Sys.Console"

# Assign permissions at cluster root
pveum acl modify / --user claude-code@pve --role ClaudeCodeManager

# Create API token -- secret piped directly into pass, never displayed
pveum user token add claude-code@pve automation --privsep 0 --output-format json \
  | jq -r '"claude-code@pve!automation\n" + .value' \
  | pass insert -m annarchy.net/pve/api-token
```

Excluded privileges: `Sys.Modify`, `Sys.PowerMgmt`, `Permissions.Modify`, `User.Modify`, `Realm.*` -- the account cannot modify host configs, reboot nodes, escalate privileges, or change auth settings.

## Credential Security

Credentials never appear in plaintext in conversation, session history, or logs.

Rules:
- Never run `pass show` as a standalone command
- Never assign the token to a variable that gets echoed
- Always use `$(pass show ...)` inline within the consuming command
- Never use `curl -v` (verbose mode leaks auth headers)
- During bootstrap, pipe token output directly into `pass insert`

API call pattern:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/version
```

The `pass` entry stores token ID on line 1 and token secret on line 2:

```
claude-code@pve!automation
<token-secret-uuid>
```

## Hybrid Execution Model

| Method | Operations |
|--------|-----------|
| REST API | VM create, start, stop, resize, migrate, status, snapshot, backup, cluster/node info, tag management, clone from template |
| SSH | Disk import (`qm importdisk`), template conversion (`qm template`), cloud image download, snippet management, ISO uploads, storage-level filesystem operations |

The skill prefers the API when both paths work. SSH is the fallback for operations requiring filesystem access on the hypervisor node.

## Runbook System

Runbooks are markdown files encoding operational procedures. The skill ships with built-in runbooks and supports adding more over time.

Runbook format:

```markdown
---
name: create-ubuntu-cloudinit-template
description: Create an Ubuntu cloud-init VM template from a cloud image
image_type: cloudinit
requires: [ssh, api]
---

# Create Ubuntu CloudInit Template

## Parameters
- distro: Ubuntu version (e.g., noble, jammy)
- image_url: Cloud image download URL
- vmid: Template ID (auto-assigned from template range if omitted)
- node: Target Proxmox node (defaults to first available)
- disk_size: Resize image to this size (default: 32G)

## Steps
1. Download cloud image to node
2. Resize image
3. Create VM with cluster defaults via API
4. Import disk via SSH
5. Configure boot order, SCSI, cloud-init drive via API
6. Write vendor snippet to node via SSH
7. Set cloud-init user, SSH keys, IP config via API
8. Apply tags via API
9. Convert to template via SSH
10. Clean up downloaded image
```

Ingesting new patterns: provide a URL or raw instructions, the skill reads the source, identifies steps needing adaptation to cluster conventions, writes a new runbook with defaults applied, and confirms before saving.

## Core Operations

**VM Lifecycle:**
- Create VM from template (clone, set resources, configure network, start)
- Start, stop, restart, shutdown (graceful and forced)
- Delete VM (with confirmation, cleans up disks)
- Resize CPU, memory, disk on existing VMs

**Template Management:**
- Create template from cloud image (cloud-init flow)
- Create template from ISO (install, configure, convert)
- Import pre-built qcow2/raw image as template
- List available templates across cluster
- Delete obsolete templates

**Migration & Evacuation:**
- Live migrate a single VM to another node
- Offline migrate (for VMs with local storage)
- Evacuate node: migrate all VMs off, respecting resource availability, with dry-run mode

**Node Status & Health:**
- Cluster overview: all nodes with CPU, memory, storage usage
- Per-node detail: running VMs, resource allocation, storage pools
- Identify overcommitted or imbalanced nodes

**Storage Management:**
- List storage pools and available space per node
- List ISOs and templates in storage
- Upload ISOs to node storage
- Clean up orphaned disks

**Bulk Operations:**
- Start/stop/restart VMs by tag
- Snapshot all VMs with a given tag
- List/filter VMs by tag, node, or status

**Backup & Snapshots:**
- Create, list, restore, delete snapshots for individual VMs
- Check scheduled backup status
- Restore VM from backup

## Cluster Lifecycle Management

Cluster profiles define entire clusters as units for fast create/destroy iteration.

Profile format (`clusters/talos-staging.yaml`):

```yaml
name: talos-staging
type: talos
network:
  api_endpoint: k0s-staging.annarchy.net:6443
  pod_cidr: 10.245.0.0/16
  service_cidr: 10.97.0.0/12
nodes:
  controlplane:
    count: 3
    cores: 4
    memory: 8192
    disk: 100G
    start_vmid: auto
    placement: spread
  workers:
    count: 0
    cores: 8
    memory: 16384
    disk: 200G
    placement: spread
template: 101
tags: [talos, kubernetes, staging]
flux:
  repo: git@github.com:adamancini/fleet-infra.git
  path: clusters/staging
  branch: main
```

Operations:
- "spin up staging" -- reads profile, clones VMs from template in parallel across nodes, applies Talos configs, bootstraps Kubernetes, optionally bootstraps Flux
- "tear down staging" -- confirms, stops and deletes all VMs by cluster tags, cleans up disks
- "rebuild staging" -- tear down then spin up in sequence

Speed comes from: cloning templates (not provisioning from ISO), parallel VM creation, pre-decided profiles with no interactive prompts, single-command teardown via tags.

Isolation: non-overlapping CIDRs per profile, distinct tags per cluster, separate Flux paths in fleet-infra.

## Ansible Integration

The skill handles interactive, ad-hoc operations directly. Multi-node orchestration delegates to fleet-infra Ansible playbooks and Taskfile.

**Direct (API/SSH):** single VM operations, template creation, node status, bulk operations via API loops.

**Delegated to Ansible:** full Talos cluster provisioning (`talos-provision-vms.yaml`), multi-node coordinated operations (rolling reboots, fleet-wide config), anything covered by existing playbooks.

Delegation constructs the right command:

```bash
ansible-playbook \
  -i ~/src/github.com/adamancini/fleet-infra/playbooks/inventories/annarchy.net/hosts.yaml \
  ~/src/github.com/adamancini/fleet-infra/playbooks/talos-provision-vms.yaml
```

The skill understands Ansible's conventions (VMID assignments, tags, network config) so direct operations don't conflict with Ansible-managed state. The skill does not modify Ansible playbooks or inventory files.

fleet-infra path: `~/src/github.com/adamancini/fleet-infra`

## Skill vs Agent Routing

- **Skill (SKILL.md):** simple operations -- check status, start a VM, list templates. Handled inline with direct API/SSH calls.
- **Agent (proxmox-manager.md):** multi-step operations that need reasoning between steps -- node evacuation (query VMs, plan placement, migrate in sequence, verify), runbook ingestion (fetch URL, adapt to conventions, write file), cluster lifecycle (parallel VM creation with progress tracking).

## Implementation Plan

Phase 1 -- Foundation:
- cluster-config.yaml with cluster topology
- SKILL.md with credential handling, API/SSH patterns, security rules
- Agent definition (proxmox-manager.md)
- RBAC bootstrap procedure

Phase 2 -- Core VM operations:
- VM lifecycle (create from template, start/stop/delete/resize)
- Node and cluster status queries
- Template listing

Phase 3 -- Template management:
- Runbook system and format
- Built-in runbooks: cloud-init, ISO, qcow2 import
- Runbook ingestion from URL/raw instructions

Phase 4 -- Advanced operations:
- Migration and node evacuation
- Bulk operations by tag
- Snapshot and backup management
- Storage management

Phase 5 -- Cluster lifecycle:
- Cluster profile format and storage
- Cluster create/destroy/rebuild
- Talos + Flux bootstrap integration
- Ansible delegation for multi-node orchestration
