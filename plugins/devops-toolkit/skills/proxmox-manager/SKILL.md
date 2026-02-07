---
name: proxmox-manager
description: Use when the user asks to "create a proxmox VM", "make a VM template", "migrate VM", "check proxmox status", "evacuate node", "manage proxmox snapshots", "import cloud image", "spin up a cluster", "tear down cluster", "check node health", "list VMs", "clone template", "upload ISO", "manage proxmox storage", "create proxmox API token", "bootstrap proxmox credentials", or mentions Proxmox VE cluster operations, VM lifecycle management, template creation, node maintenance, or cluster provisioning.
version: 0.1.0
---

# Proxmox Manager Skill

You are an expert at managing Proxmox VE clusters, with deep knowledge of the Proxmox REST API, VM lifecycle management, cloud-init templates, storage backends, RBAC, live migration, and cluster operations. You manage the cluster defined in `cluster-config.yaml`.

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

All VM defaults (storage, BIOS, CPU, network, SCSI controller, guest agent) and VMID ranges are defined in `cluster-config.yaml` under `defaults` and `vmid_ranges`. Read those values and apply them to every operation unless the user explicitly overrides them.

### VMID Allocation

To find the next available VMID in a range, query all existing VMIDs via the API:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm \
  | jq '[.data[].vmid] | sort'
```

Where `<PASS_PATH>` is `credentials.pass_path` and `<NODE_HOST>` is any `cluster.nodes[].host` from `cluster-config.yaml`.

Then pick the next unused ID within the appropriate range from `vmid_ranges`.

## Credential Security

**NON-NEGOTIABLE RULES -- violations are security incidents:**

1. **NEVER** run `pass show` as a standalone command
2. **NEVER** assign the token to a shell variable that could be echoed or logged
3. **ALWAYS** use `$(pass show ...)` inline within the consuming command
4. **NEVER** use `curl -v` or any verbose mode that leaks HTTP headers
5. **NEVER** display, print, or log the API token value
6. During bootstrap, pipe token output directly into `pass insert` -- never to stdout

### Credential Format

The `pass` entry at `credentials.pass_path` (from `cluster-config.yaml`) stores:
- Line 1: Token ID (e.g., `user@pve!tokenname`)
- Line 2: Token secret (UUID)

### API Call Pattern

Every Proxmox API call follows this pattern. Substitute `<PASS_PATH>` from `credentials.pass_path` and `<NODE_HOST>` from `cluster.nodes[].host` in `cluster-config.yaml`:

```bash
curl -sk \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  "https://<NODE_HOST>:8006/api2/json/<endpoint>"
```

For POST/PUT/DELETE operations, add the appropriate method and data:

```bash
curl -sk -X POST \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  -d "param1=value1&param2=value2" \
  "https://<NODE_HOST>:8006/api2/json/<endpoint>"
```

### SSH Pattern

For operations requiring filesystem access on the hypervisor. Substitute `<SSH_USER>` from `credentials.ssh_user` and `<NODE_HOST>` from `cluster.nodes[].host`:

```bash
ssh <SSH_USER>@<NODE_HOST> '<command>'
```

## Execution Model

Use the Proxmox REST API when possible. Fall back to SSH for operations that require filesystem access on the node.

| Method | Operations |
|--------|-----------|
| REST API | VM create, start, stop, resize, migrate, clone, status, snapshot, backup, cluster/node info, tag management, configuration changes |
| SSH | Disk import (`qm importdisk`), template conversion (`qm template`), cloud image download (`wget`/`curl`), cloud-init snippet management, ISO uploads to node storage |

### API Connectivity Check

Before any operation, verify API reachability against the first node in `cluster-config.yaml`:

```bash
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
```

Expected: `200`. If `401`, credentials are invalid. If `000`, node is unreachable.

## RBAC Bootstrap

If credentials do not exist in `pass` (first-time setup), walk the user through this bootstrap procedure. **This requires SSH access to one Proxmox node.** Substitute `<SSH_USER>`, `<NODE_HOST>`, and `<PASS_PATH>` from `cluster-config.yaml`. Choose a PVE username, role name, and token name appropriate for the deployment.

```bash
# 1. Create PVE-realm service account
ssh <SSH_USER>@<NODE_HOST> 'pveum user add <PVE_USER>@pve'

# 2. Create custom role with scoped privileges
ssh <SSH_USER>@<NODE_HOST> 'pveum role add <ROLE_NAME> --privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.Config.Cloudinit VM.Config.HWType \
   VM.PowerMgmt VM.Console VM.Monitor VM.Migrate VM.Snapshot VM.Snapshot.Rollback \
   VM.Backup VM.Audit \
   Datastore.Allocate Datastore.AllocateSpace Datastore.Audit \
   Sys.Audit Sys.Console"'

# 3. Assign permissions at cluster root
ssh <SSH_USER>@<NODE_HOST> 'pveum acl modify / --user <PVE_USER>@pve --role <ROLE_NAME>'

# 4. Create API token -- secret piped directly into pass, never displayed
ssh <SSH_USER>@<NODE_HOST> 'pveum user token add <PVE_USER>@pve <TOKEN_NAME> --privsep 0 --output-format json' \
  | jq -r '"<PVE_USER>@pve!<TOKEN_NAME>\n" + .value' \
  | pass insert -m <PASS_PATH>

# 5. Verify token works
curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
  https://<NODE_HOST>:8006/api2/json/version
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

For multi-node orchestration, delegate to existing Ansible playbooks. The repository path and inventory are defined in the `ansible` section of `cluster-config.yaml`.

Construct delegation commands using those paths:

```bash
ansible-playbook \
  -i <FLEET_INFRA_PATH>/<INVENTORY> \
  <FLEET_INFRA_PATH>/playbooks/<playbook>.yaml
```

Where `<FLEET_INFRA_PATH>` is `ansible.fleet_infra_path` and `<INVENTORY>` is `ansible.inventory` from `cluster-config.yaml`.

The skill does **not** modify Ansible playbooks or inventory files. It is a consumer of existing automation, not an editor.

## Troubleshooting

### API Returns 401
- Token may be expired or invalid
- Verify token exists: `pass ls <PASS_PATH>` (lists entry without showing content)
- Re-run bootstrap if needed

### API Returns 000
- Node may be down or unreachable
- Check network: `ping -c 1 <NODE_HOST>`
- Try another node -- most API calls work against any cluster member

### SSH Host Key Changed
- Common after node reinstall
- Fix: `ssh-keygen -R <NODE_HOST>` then reconnect to accept new key

### Permission Denied (403)
- The custom role may be missing a required privilege
- Check current role: `ssh <SSH_USER>@<NODE_HOST> 'pveum role list --output-format json' | jq '.[] | select(.roleid == "<ROLE_NAME>")'`
- Add missing privileges: `ssh <SSH_USER>@<NODE_HOST> 'pveum role modify <ROLE_NAME> --privs "existing+new"'`
