# pvesh -- Proxmox VE API Shell Interface

`pvesh` is a CLI tool that provides direct access to the Proxmox VE API from the node's shell, bypassing HTTP/HTTPS entirely. It runs as root on any PVE node.

**Official documentation:** <https://pve.proxmox.com/pve-docs/pvesh.1.html>

## When to Use pvesh vs REST API

| Scenario | Use |
|----------|-----|
| Running commands via SSH on a PVE node | `pvesh` (simpler, no auth headers needed) |
| Remote automation from a workstation | REST API with `curl` |
| Quick inspection / debugging on a node | `pvesh` (interactive, human-readable output) |
| Taskfile tasks (run from workstation) | REST API with `curl` |
| Ansible tasks delegated to PVE hosts | `pvesh` (avoids token management on-node) |

## Syntax

```
pvesh <COMMAND> <api_path> [OPTIONS] [FORMAT_OPTIONS]
```

## Commands

| Command | HTTP Method | Purpose |
|---------|------------|---------|
| `get` | GET | Read / list resources |
| `create` | POST | Create resources |
| `set` | PUT | Update resources |
| `delete` | DELETE | Remove resources |
| `ls` | -- | List child objects at a path |
| `usage` | -- | Show API usage/help for a path |

## Common Options

| Flag | Default | Description |
|------|---------|-------------|
| `--output-format <fmt>` | `text` | Output format: `text`, `json`, `json-pretty`, `yaml` |
| `--human-readable` | `1` | Convert epochs to ISO 8601, bytes to KiB/MiB/GiB, durations to human notation |
| `--noborder` | `0` | Suppress table borders |
| `--noheader` | `0` | Suppress column headers |
| `--quiet` | -- | Suppress all output |
| `--noproxy` | -- | Disable automatic proxying to the correct node |

## Authentication

`pvesh` requires **root** on the PVE node. It communicates with the API via a local Unix socket -- no HTTP tokens or tickets are needed.

**Usage pattern via SSH:**

```bash
ssh <SSH_USER>@<NODE_HOST> 'pvesh get /nodes --output-format json'
```

## REST API to pvesh Mapping

The API path in `pvesh` maps directly to the REST endpoint path (minus `/api2/json`):

| REST API | pvesh equivalent |
|----------|-----------------|
| `GET /api2/json/nodes` | `pvesh get /nodes` |
| `GET /api2/json/cluster/resources?type=vm` | `pvesh get /cluster/resources --type vm` |
| `POST /api2/json/nodes/pve01/qemu/1031/status/start` | `pvesh create /nodes/pve01/qemu/1031/status/start` |
| `PUT /api2/json/nodes/pve01/qemu/1031/config` | `pvesh set /nodes/pve01/qemu/1031/config --cores 4 --memory 8192` |
| `DELETE /api2/json/nodes/pve01/qemu/1031` | `pvesh delete /nodes/pve01/qemu/1031 --purge 1` |

**Key difference:** REST query parameters become `--flag value` CLI arguments in pvesh.

## Quick Reference Examples

### Cluster and node info

```bash
# List all nodes
pvesh get /nodes --output-format json-pretty

# Cluster status
pvesh get /cluster/status --output-format json

# Node resource usage
pvesh get /nodes/pve01/status --output-format json
```

### VM operations

```bash
# List all VMs cluster-wide
pvesh get /cluster/resources --type vm --output-format json

# VM status
pvesh get /nodes/pve01/qemu/1031/status/current --output-format json

# Start VM
pvesh create /nodes/pve01/qemu/1031/status/start

# Shutdown VM (graceful)
pvesh create /nodes/pve01/qemu/1031/status/shutdown

# Stop VM (immediate)
pvesh create /nodes/pve01/qemu/1031/status/stop

# Clone a template
pvesh create /nodes/pve01/qemu/101/clone --newid 1040 --name test-vm --full 1 --storage local-lvm

# Reconfigure VM
pvesh set /nodes/pve01/qemu/1040/config --cores 4 --memory 8192

# Resize disk
pvesh set /nodes/pve01/qemu/1040/resize --disk scsi0 --size +10G

# Delete VM
pvesh delete /nodes/pve01/qemu/1040 --purge 1 --destroy-unreferenced-disks 1
```

### Storage and templates

```bash
# List storage
pvesh get /storage --output-format json

# List templates (filter from resources)
pvesh get /cluster/resources --type vm --output-format json | jq '[.[] | select(.template == 1)]'

# Storage content
pvesh get /nodes/pve01/storage/local/content --output-format json
```

### Snapshots and tasks

```bash
# List snapshots
pvesh get /nodes/pve01/qemu/1031/snapshot --output-format json

# Create snapshot
pvesh create /nodes/pve01/qemu/1031/snapshot --snapname pre-upgrade --description "Before upgrade"

# List recent tasks
pvesh get /nodes/pve01/tasks --output-format json

# Task status
pvesh get /nodes/pve01/tasks/<UPID>/status --output-format json
```

### API discovery

```bash
# List top-level API paths
pvesh ls /

# List node sub-resources
pvesh ls /nodes/pve01

# Show usage/help for an endpoint
pvesh usage /nodes/{node}/qemu/{vmid}/config -v

# Show datacenter options
pvesh usage /cluster/options -v
```

## Output Format Details

The default `text` format applies human-readable transformations:

| Raw Value | Displayed As |
|-----------|-------------|
| Unix epoch `1708790400` | `2024-02-24 16:00:00` |
| Bytes `4294967296` | `4.00 GiB` |
| Duration `86400` | `1d 0h 0m 0s` |
| Fraction `0.42` | `42.00%` |

Use `--output-format json` or `json-pretty` for machine-parseable output. Pipe to `jq` for filtering.

## Proxying Behavior

By default, `pvesh` automatically proxies requests to the correct node if the resource lives on a different cluster member. Use `--noproxy` to disable this (e.g., when you need to target the local node specifically).
