---
topic: packer-talos-proxmox
source: https://jysk.tech/packer-and-talos-image-factory-on-proxmox-76d95e8dc316
created: 2026-02-20
updated: 2026-02-20
tags:
  - packer
  - talos
  - proxmox
  - image-factory
  - template-automation
  - hashicorp
---

# Packer + Talos Image Factory on Proxmox

## Summary

An automated approach to creating Talos Linux VM templates on Proxmox using HashiCorp Packer and the Talos Image Factory API. Packer boots a lightweight live OS (Arch Linux), downloads a custom Talos image via the factory API with a schematic defining extensions, and writes it directly to disk using `dd`. The VM is then shut down and converted to a reusable template. This enables fully automated, CI-driven template creation for Talos version upgrades.

## Key Concepts

### Architecture

The Packer workflow differs from the standard SSH-based template creation in a fundamental way: instead of downloading the image externally and importing it via `qm set --import-from`, Packer boots a live OS inside the VM itself and writes the Talos image from within. This enables:

- **Full automation via CI/CD** -- no SSH access to hypervisor nodes required
- **API-only interaction** with Proxmox via the `hashicorp/proxmox` Packer plugin
- **Reproducible builds** from a single HCL configuration
- **Version pinning** through variable files

### Packer Plugin

Uses the `github.com/hashicorp/proxmox` plugin (>= 1.1.7) with the `proxmox-iso` builder. The builder creates a VM from an ISO, manages its lifecycle, and converts it to a template after provisioning.

### Boot Command Technique

Packer's `boot_command` sends keystrokes to the VM console to configure the live OS (Arch Linux) for network access:

```hcl
boot_command = [
  "<enter><wait50s>",
  "passwd<enter><wait1s>packer<enter><wait1s>packer<enter>",
  "ip address add ${var.static_ip} broadcast + dev ens18<enter><wait>",
  "ip route add 0.0.0.0/0 via ${var.gateway} dev ens18<enter><wait>",
  "ip link set dev ens18 mtu 1300<enter>",
]
```

This sets up a root password (for SSH provisioning) and configures a static IP. The MTU setting addresses specific network constraints.

### Talos Image Factory Schematic

The factory API accepts a YAML schematic defining extensions to bake into the image. The schematic is uploaded via POST, returning a deterministic ID used to construct the download URL:

```yaml
# files/schematic.yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
```

The build provisioner uploads this schematic, retrieves the ID, and downloads the NoCloud image:

```bash
ID=$(curl -kLX POST --data-binary @/tmp/schematic.yaml https://factory.talos.dev/schematics \
  | grep -o '"id":"[^"]*' | sed 's/"id":"//')
URL=https://pxe.factory.talos.dev/image/$ID/${var.talos_version}/nocloud-amd64.raw.xz
curl -kL "$URL" -o /tmp/talos.raw.xz
xz -d -c /tmp/talos.raw.xz | dd of=/dev/vda && sync
```

### Dual Disk Layout

The Packer build defines two disks:
- **Disk 1 (20 GB):** Talos OS -- the factory image is written here via `dd`
- **Disk 2 (10 GB):** Local storage provisioner for Kubernetes workloads

Both use virtio block devices (`/dev/vda`, `/dev/vdb`).

### Template Naming Convention

Templates are named with version and hypervisor type for identification:
- Pattern: `talos-template-${var.talos_version}-qemu`
- Tags: `${var.talos_version};template`
- Description includes build timestamp for traceability

## Practical Application

### Project Structure

```
talos_packer/
  proxmox.pkr.hcl           # Main build definition (source + build blocks)
  variables.pkr.hcl         # Variable declarations
  vars/
    local.pkrvars.hcl       # Environment-specific values
  files/
    schematic.yaml           # Talos Image Factory extension schema
```

### Required Variables

| Variable | Purpose |
|----------|---------|
| `proxmox_username` | PVE API token ID (e.g., `user@pve!packer`) |
| `proxmox_token` | PVE API token secret |
| `proxmox_url` | PVE API URL (e.g., `https://pve.domain.com:8006/api2/json`) |
| `proxmox_nodename` | Target PVE node |
| `proxmox_storage` | Storage backend for VM disks |
| `proxmox_storage_type` | Storage type (e.g., `lvm`) |
| `static_ip` | Static IP for the live Arch VM (with CIDR, e.g., `10.0.30.163/25`) |
| `gateway` | Gateway for the live Arch VM |
| `talos_version` | Talos version to build (default: `v1.9.2`) |

### Build Command

```bash
export PROXMOX_TOKEN_ID='user@domain.com!packer'
export PROXMOX_TOKEN_SECRET='my-key'
export PROXMOX_HOST="https://pve.domain.com:8006/api2/json"
export PROXMOX_NODE_NAME="my-node-name"

packer build -on-error=ask \
  -var-file="vars/local.pkrvars.hcl" \
  -var proxmox_username="${PROXMOX_TOKEN_ID}" \
  -var proxmox_token="${PROXMOX_TOKEN_SECRET}" \
  -var proxmox_nodename="${PROXMOX_NODE_NAME}" \
  -var proxmox_url="${PROXMOX_HOST}" .
```

### Version Upgrade Workflow

To create a template for a new Talos version:
1. Update `talos_version` in `vars/local.pkrvars.hcl`
2. Update `schematic.yaml` if extensions change
3. Run `packer build` with the same command
4. Old templates remain intact -- new template gets a unique name

## Decision Points

### Packer vs SSH-Based Template Creation

| Factor | Packer Approach | SSH Approach (existing runbook) |
|--------|----------------|-------------------------------|
| Hypervisor SSH access | Not required | Required for `qm create`, disk import |
| Automation | CI/CD native (HCL config) | Scripted but manual SSH steps |
| Prerequisites | Packer binary, Arch ISO on PVE, network for live VM | SSH key, `qm` CLI on node |
| Network requirements | Live VM needs IP + internet access to factory API | Node needs internet for `wget` |
| Complexity | Higher (boot commands, live OS, SSH provisioning) | Lower (direct disk import) |
| UEFI/BIOS | Uses default SeaBIOS (article example) | Uses OVMF (UEFI required for Talos) |
| Disk controller | virtio (block device) | virtio-scsi-single |
| Proxy support | Built-in via shell provisioner env vars | N/A |

### When to Use Packer

- CI/CD pipeline for automated template builds on version release
- Environments where SSH access to hypervisors is restricted
- Multi-node deployments where templates need building on different nodes
- Teams using Packer for other image builds (consistent tooling)

### When to Use SSH-Based Approach

- One-off template creation
- Small environments with direct hypervisor access
- When UEFI boot (OVMF) is required (Packer example uses SeaBIOS -- would need adjustment)
- Simpler operational model with fewer moving parts

### Adaptation Notes for Existing Proxmox-Manager Conventions

The article's Packer build uses some settings that differ from the proxmox-manager cluster defaults:

- **BIOS:** Article uses default (SeaBIOS). Talos requires OVMF for UEFI boot. Adapt by adding `bios = "ovmf"` and an EFI disk.
- **SCSI controller:** Article uses `virtio-scsi-pci`. Cluster default is `virtio-scsi-single`. Adapt as needed.
- **Disk format:** Article uses `qcow2`. Consider `raw` on LVM-thin for better performance.
- **SSH timeout:** 15 minutes -- reasonable for image download over factory API.
- **Guest agent:** Enabled (`qemu_agent = true`), matching the `siderolabs/qemu-guest-agent` extension in the schematic.
- **Proxy support:** The article includes proxy configuration in the shell provisioner. Remove if not needed, or adapt to your proxy settings.

## References

- [Packer Proxmox Plugin Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [Talos Image Factory](https://factory.talos.dev/)
- [Talos Image Factory Docs](https://www.talos.dev/latest/talos-guides/install/boot-assets/)
- [Original Article: 3000+ Clusters Part 2 (JYSK)](https://jysk.tech/) -- context for edge-scale Talos deployments
- [Packer Boot Command Reference](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso#boot-configuration)
