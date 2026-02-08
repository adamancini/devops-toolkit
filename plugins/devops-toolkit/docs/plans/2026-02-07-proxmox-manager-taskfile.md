# Proxmox Manager Taskfile: CLI Wrapper for Common Operations

**Date:** 2026-02-07
**Status:** Implemented
**Version:** 0.6.0

## Summary

Added a go-task `Taskfile.yml` to the proxmox-manager skill that wraps common
Proxmox API operations as ergonomic one-liners. This replaces the need to
manually construct multi-line curl commands for repeated patterns like clone,
configure, migrate, resize, and start.

## Motivation

During real sessions (e.g., creating k0s01-03), constructing curl commands with
inline `pass show` credential resolution was tedious and error-prone for
repeated operations. A Taskfile provides:

- One-liner commands for common operations
- Automatic node resolution (query cluster/resources for VMID placement)
- Credential security (pass evaluated at runtime in bash, never stored)
- Interactive confirmation prompts for destructive operations
- Full cluster lifecycle from profile YAML files

## Design Decisions

### Credential Security

`PVE_AUTH` contains `$(pass show ...)` as a literal string. Taskfile's Go
template engine passes this through to bash without evaluation. The credential
is only resolved at runtime inside the curl command and never lands in a shell
variable or process environment.

### Same-Node Clone Pattern

`pve:vm:clone` always clones to the template's node to avoid
`can't clone to non-shared storage 'local-lvm'` errors. To place a VM on
another node, clone first then migrate. The `pve:cluster:create` task handles
this workflow automatically.

### Node Resolution

VM operations resolve the hosting node by querying `cluster/resources` with the
VMID. This avoids requiring the user to know which node a VM is on.

### IP Gateway Derivation

`pve:vm:set` accepts IP in CIDR notation (e.g., `IP=10.0.0.31/24`) and derives
the gateway as the `.1` address of the subnet. This matches the common network
convention for the annarchy.net cluster.

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `skills/proxmox-manager/Taskfile.yml` | Created | 22 tasks wrapping Proxmox API operations |
| `skills/proxmox-manager/SKILL.md` | Edited | Added Taskfile CLI section, bumped to v0.6.0 |
| `docs/plans/2026-02-07-proxmox-manager-taskfile.md` | Created | This plan document |

## Task Inventory

### Help (2)
- `default` -- list all tasks
- `pve:check` -- verify API connectivity to all 3 nodes

### Status (6)
- `pve:status` -- cluster health
- `pve:status:node` -- per-node resources (requires `NODE`)
- `pve:vms` -- all VMs (tabular)
- `pve:vms:running` -- running VMs only
- `pve:vms:by-tag` -- filter by `TAG`
- `pve:templates` -- list templates

### VM Lifecycle (10)
- `pve:vm:clone` -- clone template (requires `TEMPLATE`, `VMID`, `NAME`)
- `pve:vm:start` -- start VM
- `pve:vm:stop` -- graceful ACPI shutdown
- `pve:vm:kill` -- force stop (prompted)
- `pve:vm:delete` -- delete with purge (prompted, auto-stops)
- `pve:vm:resize` -- grow disk (`DISK` defaults to scsi0)
- `pve:vm:config` -- show config
- `pve:vm:set` -- set config (CORES, MEMORY, TAGS, IP)
- `pve:vm:migrate` -- migrate (ONLINE defaults to 0)
- `pve:task:wait` -- poll UPID until completion

### Cluster Lifecycle (4)
- `pve:cluster:list` -- list profiles from clusters/*.yaml
- `pve:cluster:status` -- VMs matching profile tags
- `pve:cluster:create` -- full provision from profile
- `pve:cluster:teardown` -- destroy all VMs by tags (prompted)
