# Proxmox Manager Phase 1: Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the proxmox-manager skill, agent, and cluster configuration files so that Claude Code can authenticate to the Proxmox cluster and execute basic API/SSH operations.

**Architecture:** A skill (SKILL.md) defines conventions, credential patterns, and operational knowledge. An agent (proxmox-manager.md) handles multi-step reasoning. A cluster config (cluster-config.yaml) grounds operations in the user's environment. Credentials use `pass` with inline command substitution to avoid plaintext exposure.

**Tech Stack:** Claude Code skill/agent (markdown), YAML config, Proxmox REST API, SSH, `pass` password store, `curl`, `jq`

---

### Task 1: Create skill directory structure

**Files:**
- Create: `skills/proxmox-manager/`
- Create: `skills/proxmox-manager/runbooks/`
- Create: `skills/proxmox-manager/clusters/`

**Step 1: Create directories**

```bash
mkdir -p ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager/runbooks
mkdir -p ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager/clusters
```

**Step 2: Verify structure**

```bash
find ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager -type d
```

Expected: three directories listed (proxmox-manager, runbooks, clusters)

---

### Task 2: Write cluster-config.yaml

**Files:**
- Create: `skills/proxmox-manager/cluster-config.yaml`

**Step 1: Write the cluster configuration**

Write the following to `skills/proxmox-manager/cluster-config.yaml`:

```yaml
# Proxmox cluster topology and conventions.
# The proxmox-manager skill reads this file at invocation
# to ground all operations in this environment.

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

ansible:
  fleet_infra_path: ~/src/github.com/adamancini/fleet-infra
  inventory: playbooks/inventories/annarchy.net/hosts.yaml
```

**Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('$HOME/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager/cluster-config.yaml'))" && echo "Valid YAML"
```

Expected: "Valid YAML"

---

### Task 3: Write the SKILL.md

**Files:**
- Create: `skills/proxmox-manager/SKILL.md`

**Step 1: Write the skill definition**

Write the following to `skills/proxmox-manager/SKILL.md`:

````markdown
---
name: proxmox-manager
description: Use when the user asks to "create a proxmox VM", "make a VM template", "migrate VM", "check proxmox status", "evacuate node", "manage proxmox snapshots", "import cloud image", "spin up a cluster", "tear down cluster", "check node health", "list VMs", "clone template", "upload ISO", "manage proxmox storage", "create proxmox API token", "bootstrap proxmox credentials", or mentions Proxmox VE cluster operations, VM lifecycle management, template creation, node maintenance, or cluster provisioning.
version: 0.1.0
---

# Proxmox Manager Skill

You are an expert at managing Proxmox VE clusters, with deep knowledge of the Proxmox REST API, VM lifecycle management, cloud-init templates, storage backends, RBAC, live migration, and cluster operations. You manage the annarchy.net Proxmox cluster.

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

## Cluster Configuration

**CRITICAL:** Before any operation, read the cluster configuration file at:
`skills/proxmox-manager/cluster-config.yaml` (relative to the skill directory)

This file defines the cluster topology, VM defaults, VMID ranges, credential paths, and conventions. Apply these defaults to every operation unless the user explicitly overrides them.

### Key Conventions

- **Storage:** `local-lvm` (not local-zfs)
- **BIOS:** OVMF (UEFI) with q35 machine type
- **CPU:** host passthrough
- **SCSI:** virtio-scsi-single with iothread
- **Network:** virtio on vmbr0
- **Guest agent:** always enabled
- **Template VMIDs:** 100-999
- **VM VMIDs:** 1000-9999

### VMID Allocation

To find the next available VMID in a range, query all existing VMIDs via the API:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/cluster/resources?type=vm \
  | jq '[.data[].vmid] | sort'
```

Then pick the next unused ID within the appropriate range (100-999 for templates, 1000-9999 for VMs).

## Credential Security

**NON-NEGOTIABLE RULES -- violations are security incidents:**

1. **NEVER** run `pass show` as a standalone command
2. **NEVER** assign the token to a shell variable that could be echoed or logged
3. **ALWAYS** use `$(pass show ...)` inline within the consuming command
4. **NEVER** use `curl -v` or any verbose mode that leaks HTTP headers
5. **NEVER** display, print, or log the API token value
6. During bootstrap, pipe token output directly into `pass insert` -- never to stdout

### Credential Format

The `pass` entry at `annarchy.net/pve/api-token` stores:
- Line 1: Token ID (`claude-code@pve!automation`)
- Line 2: Token secret (UUID)

### API Call Pattern

Every Proxmox API call follows this pattern:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  "https://<node>.annarchy.net:8006/api2/json/<endpoint>"
```

For POST/PUT/DELETE operations, add the appropriate method and data:

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  -d "param1=value1&param2=value2" \
  "https://<node>.annarchy.net:8006/api2/json/<endpoint>"
```

### SSH Pattern

For operations requiring filesystem access on the hypervisor:

```bash
ssh root@<node>.annarchy.net '<command>'
```

## Execution Model

Use the Proxmox REST API when possible. Fall back to SSH for operations that require filesystem access on the node.

| Method | Operations |
|--------|-----------|
| REST API | VM create, start, stop, resize, migrate, clone, status, snapshot, backup, cluster/node info, tag management, configuration changes |
| SSH | Disk import (`qm importdisk`), template conversion (`qm template`), cloud image download (`wget`/`curl`), cloud-init snippet management, ISO uploads to node storage |

### API Connectivity Check

Before any operation, verify API reachability:

```bash
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/version
```

Expected: `200`. If `401`, credentials are invalid. If `000`, node is unreachable.

## RBAC Bootstrap

If credentials do not exist in `pass` (first-time setup), walk the user through this bootstrap procedure. **This requires SSH access as root to one Proxmox node.**

```bash
# 1. Create PVE-realm service account
ssh root@pve01.annarchy.net 'pveum user add claude-code@pve'

# 2. Create custom role with scoped privileges
ssh root@pve01.annarchy.net 'pveum role add ClaudeCodeManager --privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType \
   VM.PowerMgmt VM.Console VM.Monitor VM.Migrate VM.Snapshot VM.Snapshot.Rollback \
   VM.Backup VM.Audit \
   Datastore.Allocate Datastore.AllocateSpace Datastore.Audit \
   Sys.Audit Sys.Console"'

# 3. Assign permissions at cluster root
ssh root@pve01.annarchy.net 'pveum acl modify / --user claude-code@pve --role ClaudeCodeManager'

# 4. Create API token -- secret piped directly into pass, never displayed
ssh root@pve01.annarchy.net 'pveum user token add claude-code@pve automation --privsep 0 --output-format json' \
  | jq -r '"claude-code@pve!automation\n" + .value' \
  | pass insert -m annarchy.net/pve/api-token

# 5. Verify token works
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/version
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

Cluster profiles live in `skills/proxmox-manager/clusters/`. Each profile defines an entire cluster as a unit for fast create/destroy cycles. See the design document for the profile format.

## Ansible Integration

For multi-node orchestration, delegate to existing fleet-infra Ansible playbooks. The fleet-infra repository is at `~/src/github.com/adamancini/fleet-infra`.

Construct delegation commands using the inventory and playbook paths from `cluster-config.yaml`:

```bash
ansible-playbook \
  -i ~/src/github.com/adamancini/fleet-infra/playbooks/inventories/annarchy.net/hosts.yaml \
  ~/src/github.com/adamancini/fleet-infra/playbooks/<playbook>.yaml
```

The skill does **not** modify Ansible playbooks or inventory files. It is a consumer of existing automation, not an editor.

## Troubleshooting

### API Returns 401
- Token may be expired or invalid
- Verify token exists: `pass ls annarchy.net/pve/api-token` (lists entry without showing content)
- Re-run bootstrap if needed

### API Returns 000
- Node may be down or unreachable
- Check network: `ping -c 1 <node>.annarchy.net`
- Try another node -- most API calls work against any cluster member

### SSH Host Key Changed
- Common after node reinstall
- Fix: `ssh-keygen -R <node>.annarchy.net` then reconnect to accept new key

### Permission Denied (403)
- The ClaudeCodeManager role may be missing a required privilege
- Check current role: `ssh root@<node> 'pveum role list --output-format json' | jq '.[] | select(.roleid == "ClaudeCodeManager")'`
- Add missing privileges: `ssh root@<node> 'pveum role modify ClaudeCodeManager --privs "existing+new"'`
````

**Step 2: Verify the file was created and has the frontmatter**

```bash
head -5 ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager/SKILL.md
```

Expected: YAML frontmatter starting with `---`

---

### Task 4: Write the agent definition

**Files:**
- Create: `agents/proxmox-manager.md`

**Step 1: Write the agent**

Write the following to `agents/proxmox-manager.md`:

````markdown
---
name: proxmox-manager
description: Use this agent when you need to perform multi-step Proxmox VE operations that require reasoning between steps. This includes node evacuation (query VMs, plan placement, migrate in sequence, verify), template creation from external sources (fetch instructions, adapt to cluster conventions, execute), cluster lifecycle management (parallel VM creation, Talos bootstrap, Flux setup), and runbook ingestion (fetch URL, adapt procedures, write runbook files). For simple single-step operations (check status, start a VM, list templates), the proxmox-manager skill handles those inline without needing this agent.
model: sonnet
color: blue
skills: proxmox-manager
---

You are an expert Proxmox VE cluster operator managing the annarchy.net cluster (pve01, pve02, pve03). You handle complex, multi-step infrastructure operations that require reasoning between steps, checking intermediate state, and adapting your approach based on results.

## Before Any Operation

1. Read the cluster configuration: `skills/proxmox-manager/cluster-config.yaml`
2. Read available runbooks in `skills/proxmox-manager/runbooks/`
3. Read cluster profiles in `skills/proxmox-manager/clusters/` if the operation involves cluster lifecycle
4. Verify API connectivity to at least one node

## Credential Security

**These rules are non-negotiable:**
- NEVER run `pass show` as a standalone command
- NEVER assign credentials to variables that could be echoed
- ALWAYS use `$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)` inline within curl commands
- NEVER use `curl -v` (leaks auth headers)

## Core Responsibilities

### Multi-Step VM Operations
When an operation involves several API/SSH calls with dependencies between them:
- Execute each step and verify the result before proceeding
- If a step fails, report the error clearly and stop -- do not blindly continue
- For destructive operations (delete, evacuate), always confirm with the user first

### Node Evacuation
1. Query all VMs on the target node via API
2. Query resource availability on all other nodes
3. Plan VM placement: spread VMs across available nodes respecting resource limits
4. Present the migration plan to the user for approval (dry-run by default)
5. Execute migrations one at a time, verifying each completes
6. Confirm all VMs are off the target node

### Template Creation
1. Read the appropriate runbook for the template type
2. If no runbook exists, adapt the user's instructions to cluster conventions
3. Execute each step, verifying success at each stage
4. Apply standard tags from cluster config
5. Verify the template is usable by checking its config via API

### Runbook Ingestion
When the user provides a URL or instructions for a new procedure:
1. Fetch and read the source material
2. Map each step to the cluster's conventions (storage, network, VMID range, BIOS, etc.)
3. Write a runbook file following the format in `runbooks/_template.md`
4. Present the adapted runbook to the user for review
5. Save only after user approval

### Cluster Lifecycle
1. Read the cluster profile for the requested cluster
2. Clone VMs from the specified template across nodes (respecting placement strategy)
3. Wait for all VMs to be running
4. If Talos type: apply Talos machine configs, bootstrap Kubernetes
5. If Flux config specified: bootstrap Flux CD
6. For teardown: confirm with user, stop all VMs by tag, delete, clean up disks

## Execution Preferences

- **API over SSH** when both can accomplish the task
- **Parallel operations** when steps are independent (e.g., creating multiple VMs)
- **Sequential with verification** when steps depend on each other
- **Dry-run first** for destructive or large-scale operations

## Ansible Delegation

For operations already covered by fleet-infra playbooks, delegate rather than reimplement:
- Full Talos cluster provisioning: `talos-provision-vms.yaml`
- Multi-node coordinated operations: use existing playbooks
- Construct commands using paths from `cluster-config.yaml`

The skill does not modify Ansible playbooks or inventory files.

## Error Handling

- Always check HTTP status codes from API calls
- For SSH commands, check exit codes
- On failure, report: what was attempted, what failed, the error message, and suggested remediation
- Never retry destructive operations automatically
````

**Step 2: Verify the file was created**

```bash
head -8 ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/agents/proxmox-manager.md
```

Expected: YAML frontmatter with name, description, model, color, skills

---

### Task 5: Write the runbook template

**Files:**
- Create: `skills/proxmox-manager/runbooks/_template.md`

**Step 1: Write the template**

Write the following to `skills/proxmox-manager/runbooks/_template.md`:

```markdown
---
name: procedure-name
description: One-line description of what this procedure does
image_type: cloudinit | iso | qcow2 | raw | none
requires: [api, ssh]
---

# Procedure Title

## Parameters

- param_name: Description (default: value)
- param_name: Description (required)

## Prerequisites

- List any prerequisites (e.g., "ISO must be uploaded to node storage")

## Steps

1. **Step description** (API|SSH)
   ```bash
   command here
   ```
   Expected result: description

2. **Next step** (API|SSH)
   ```bash
   command here
   ```
   Expected result: description

## Cleanup

- List any cleanup actions (e.g., "Remove downloaded image from /tmp")

## Notes

- Any important caveats or variations
```

**Step 2: Verify the file**

```bash
head -5 ~/.claude/plugins/marketplaces/devops-toolkit/plugins/devops-toolkit/skills/proxmox-manager/runbooks/_template.md
```

Expected: YAML frontmatter starting with `---`

---

### Task 6: Fix SSH host key for pve01

**Prerequisite:** This must succeed before Task 7 (RBAC bootstrap).

**Step 1: Remove stale host key**

```bash
ssh-keygen -R pve01.annarchy.net
```

Expected: "Host pve01.annarchy.net found" and key removed

**Step 2: Verify SSH connectivity (accept new key)**

```bash
ssh -o StrictHostKeyChecking=accept-new root@pve01.annarchy.net 'hostname && pveversion'
```

Expected: hostname and PVE version printed. The new host key is saved automatically.

**Step 3: Verify SSH to all nodes**

```bash
ssh root@pve01.annarchy.net 'pveversion'
ssh root@pve02.annarchy.net 'pveversion'
ssh root@pve03.annarchy.net 'pveversion'
```

Expected: PVE version from all three nodes

---

### Task 7: Bootstrap RBAC and API credentials

**Prerequisite:** Task 6 (SSH working). This task runs commands on live Proxmox nodes.

**Step 1: Create PVE-realm service account**

```bash
ssh root@pve01.annarchy.net 'pveum user add claude-code@pve'
```

Expected: no error output (silent success)

**Step 2: Create custom role**

```bash
ssh root@pve01.annarchy.net 'pveum role add ClaudeCodeManager --privs "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType VM.PowerMgmt VM.Console VM.Monitor VM.Migrate VM.Snapshot VM.Snapshot.Rollback VM.Backup VM.Audit Datastore.Allocate Datastore.AllocateSpace Datastore.Audit Sys.Audit Sys.Console"'
```

Expected: no error output (silent success)

**Step 3: Assign permissions**

```bash
ssh root@pve01.annarchy.net 'pveum acl modify / --user claude-code@pve --role ClaudeCodeManager'
```

Expected: no error output (silent success)

**Step 4: Create API token and store in pass**

```bash
ssh root@pve01.annarchy.net 'pveum user token add claude-code@pve automation --privsep 0 --output-format json' \
  | jq -r '"claude-code@pve!automation\n" + .value' \
  | pass insert -m annarchy.net/pve/api-token
```

Expected: pass confirms the entry was created. The token secret never appears in output.

**Step 5: Verify API access**

```bash
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/version
```

Expected: `200`

**Step 6: Verify against all nodes**

```bash
for node in pve01 pve02 pve03; do
  echo -n "$node: "
  curl -sk -o /dev/null -w "%{http_code}\n" \
    -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
    "https://$node.annarchy.net:8006/api2/json/version"
done
```

Expected: `200` from all three nodes

---

### Task 8: Smoke test -- fetch cluster status via API

**Step 1: Query cluster status**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/cluster/status \
  | jq '.data[] | {name, type, online}'
```

Expected: JSON objects for each node showing name, type ("node"), and online status (1)

**Step 2: Query all VMs across cluster**

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show annarchy.net/pve/api-token | head -1)=$(pass show annarchy.net/pve/api-token | tail -1)" \
  https://pve01.annarchy.net:8006/api2/json/cluster/resources?type=vm \
  | jq '.data[] | {vmid, name, node, status, type}'
```

Expected: JSON listing of all VMs/containers in the cluster

---

### Task 9: Commit

**Step 1: Stage new files**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/devops-toolkit/skills/proxmox-manager/
git add plugins/devops-toolkit/agents/proxmox-manager.md
git add plugins/devops-toolkit/docs/plans/2026-02-07-proxmox-manager-design.md
git add plugins/devops-toolkit/docs/plans/2026-02-07-proxmox-manager-phase1.md
```

**Step 2: Review staged changes**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit && git diff --cached --stat
```

Expected: new files listed

**Step 3: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit && git commit -m "$(cat <<'EOF'
feat: add proxmox-manager skill, agent, and cluster config

Phase 1 foundation for Proxmox VE cluster management:
- SKILL.md with credential security rules, API/SSH patterns,
  RBAC bootstrap procedure, and runbook system
- Agent definition for multi-step operations
- Cluster config for annarchy.net topology and conventions
- Runbook template format
- Design document and implementation plan
EOF
)"
```

**Step 4: Push**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit && git push origin main
```
