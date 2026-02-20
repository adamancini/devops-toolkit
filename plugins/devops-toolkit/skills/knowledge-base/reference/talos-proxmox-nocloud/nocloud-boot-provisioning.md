---
topic: talos-proxmox-nocloud
source: https://jysk.tech/3000-clusters-part-3-how-to-boot-talos-linux-nodes-with-cloud-init-and-nocloud-acdce36f60c0
created: 2026-02-20
updated: 2026-02-20
tags:
  - talos
  - proxmox
  - cloud-init
  - nocloud
  - provisioning
  - infrastructure-as-code
---

# Talos Linux NoCloud Boot Provisioning on Proxmox

## Summary

Talos Linux supports a `nocloud` cloud-init datasource for automated VM configuration injection at boot. Two modes exist: SMBIOS serial (network-based HTTP config fetch) and CDROM/ISO (local storage). SMBIOS-based nocloud-net is the scalable pattern -- JYSK used it to provision 3,000+ store clusters by encoding a per-VM config-server URL in the Proxmox SMBIOS serial field via `qm set`. The `nocloud` image variant from factory.talos.dev must be used (not `metal`). Source: Ryan Gough (Feb 6 2025), full article text confirmed.

## Key Concepts

### Image Selection

| Image | Cloud-Init | Usage |
|-------|-----------|-------|
| `nocloud-amd64.iso` | Yes | Proxmox via ISO attachment |
| `nocloud-amd64.raw.xz` | Yes | Terraform bpg provider (decompress first) |
| `metal-amd64.iso` | No | Bare metal only |

Factory.talos.dev URL pattern:
```
https://factory.talos.dev/image/<schematic-hash>/<version>/nocloud-amd64.iso
```

### Datasource Mode 1: SMBIOS Serial (nocloud-net)

SMBIOS type-1 serial field format:
```
ds=nocloud-net;s=http://<server>/configs/;h=<hostname>
```

Talos uses `go-smbios` to read the SERIAL field at boot, which triggers cloud-init provisioning through the no-cloud "line configuration" specification. Talos fetches:
- `<url>/user-data` - Talos machine configuration YAML (required)
- `<url>/meta-data` - `local-hostname: <name>` (optional)
- `<url>/network-config` - Cloud-init v1 network format (optional)

Requires DHCP network connectivity at first boot. Credentials can be embedded in the URL:
```
ds=nocloud-net;s=https://user:pass@api.domain.com/store/<DEVICE>/;h=<HOSTNAME>
```

### Datasource Mode 2: CDROM/ISO (local)

Filesystem labeled `cidata` or `CIDATA` (VFAT or ISO9660) containing the same files. No network required at boot.

ISO creation:
```bash
genisoimage -output cidata.iso -V cidata -r -J user-data meta-data network-config
```

### JYSK Go API Architecture (production reference)

For 3000+ clusters, JYSK built a Go API (Fiber framework) backed by Postgres. Provisioner pattern:

```go
type Provisioner interface {
 Retrieve() (existing bool, err error)
 AddToDB() (err error)
 ReturnControlPlane() []byte
}

type provisioner struct {
 Device      string
 Node        net.IP
 Bundle      *bundle.Bundle
 DeviceMeta  meta.Metadata
 TalosConfig *model.TalosConfig
}
```

Uses Talos Machinery packages directly for config generation:
```go
"github.com/siderolabs/talos/pkg/machinery/config/bundle"
"github.com/siderolabs/talos/pkg/machinery/config/generate"
"github.com/siderolabs/talos/pkg/machinery/config/machine"
"github.com/siderolabs/talos/pkg/machinery/config/types/v1alpha1"
```

Routes (Fiber, with HTTP basic auth per device):
```go
storeGroup := app.Group("/store/:device", basicAuth)
storeGroup.Get("/user-data", handlers.ReturnUserDate)
storeGroup.Get("/meta-data", handlers.ReturnMetaData)
storeGroup.Get("/network-config", handlers.ReturnNetworkConfig)
storeGroup.Get("/smi", handlers.ReturnSMI)
```

Reset flag pattern: when a node needs fresh config (upgrade, hardware change), flag existing config for deletion. Old certs/TalosConfig/KubeConfig retained until node is ready. Enables smooth automated transitions.

## Practical Application

### Proxmox SMBIOS Configuration (CLI)

The serial field must be base64-encoded when set via CLI. Always preserve the existing UUID.

```bash
# Build the nocloud-net spec
SMBIOSSERIAL="ds=nocloud-net;s=http://10.10.0.1/configs/node1/;h=node1"

# Encode (no line wrap)
NEW_SERIAL=$(echo ${SMBIOSSERIAL} | base64 -w 0)

# Preserve existing UUID
UUID=$(qm config ${VMID} | grep smbios1 | grep -oP 'uuid=\K[^,]+')

# Apply -- MUST include UUID or it gets reset
qm set ${VMID} --smbios1 "uuid=${UUID},serial=${NEW_SERIAL},base64=1"
```

Resulting config line in `/etc/pve/qemu-server/<VMID>.conf`:
```
smbios1: uuid=5b0f7dcf-...,serial=ZHM9bm9jbG91ZC1uZXQ7...,base64=1
```

Proxmox UI (VM > Options > SMBIOS Settings) handles base64 encoding automatically.

### JYSK Full Provisioning Script (clone + SMBIOS + network + tags + ACLs)

```bash
#!/bin/bash
set -e
VMNAME=$(hostname | sed -e 's/pve/k8s/i')
SMBIOSSERIAL="ds=nocloud-net;s=https://talos.domain.com/store/${VMNAME}/;h=${VMNAME}"
VMID=3002
TEMPLATEID=100

# Create linked clone of template
/usr/sbin/qm clone ${TEMPLATEID} ${VMID} --name ${VMNAME}

# Set Serial
NEW_SERIAL_NUMBER=$(echo ${SMBIOSSERIAL} | base64 -w 0)
SMBIOS1=$(/usr/sbin/qm config ${VMID} | grep smbios1)
UUID=$(echo ${SMBIOS1} | sed -n 's/.*uuid=\([^,]*\).*/\1/p')
/usr/sbin/qm set ${VMID} --smbios1 uuid=${UUID},serial=${NEW_SERIAL_NUMBER},base64=1

# Update network
/usr/sbin/qm set ${VMID} --net0 model=virtio,bridge=vmbr1,mtu=1300

echo "Updated VM ${VMID} with new serial number ${NEW_SERIAL_NUMBER} (UUID: ${UUID})"

# Tags -- strip 'template' tag inherited from clone source
sed -i -E 's/(;)?template(;)?//g; s/^tags: ;/tags: /; s/;;/;/g; s/;$//' /etc/pve/qemu-server/${VMID}.conf

# ACLs
pvesh set /access/acl -path /vms/${VMID} -roles PVEVMUser -groups GROUP_ADMIN

/usr/sbin/qm start ${VMID}
```

Notes: `hostname | sed 's/pve/k8s/i'` derives VM name from PVE host name. `base64 -w 0` disables line wrapping (critical).

### Terraform/OpenTofu (Telmate proxmox provider)

```hcl
resource "proxmox_vm_qemu" "talos-k8s01" {
  name        = local.name
  target_node = "hypervisor node"
  cores       = 2
  sockets     = 2
  cpu         = "host"
  memory      = 6144
  onboot      = true
  agent       = 1
  clone       = "talos-template-v1.9.1-qemu"
  full_clone  = true
  bootdisk    = "virtio0"

  network {
    model  = "virtio"
    bridge = "vmbr1"
    mtu    = 1300
  }

  scsihw = "virtio-scsi-pci"

  disks {
    virtio {
      virtio0 {
        disk { size = 20; storage = "local"; format = "qcow2" }
      }
      virtio1 {
        disk { size = 10; storage = "local"; format = "qcow2"; backup = true }
      }
    }
  }

  smbios {
    serial = "ds=nocloud-net;s=https://user:pass@talos.domain.com/store/${local.name}/;h=${local.name};"
  }
}
```

### Proxmox cicustom (snippet-based, simpler for small clusters)

```bash
# Enable snippets on storage (one-time)
pvesm set local --content iso,snippets

# Upload machine config
cp controlplane-1.yaml /var/lib/vz/snippets/

# Attach to VM
qm set 100 --cicustom user=local:snippets/controlplane-1.yaml
```

Terraform (bpg provider):
```hcl
resource "proxmox_virtual_environment_file" "user-data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve01"
  source_raw {
    data      = file("talos/generated/controlplane-1.yaml")
    file_name = "controlplane-1.yaml"
  }
}
```

### network-config Format (Cloud-Init v1)

```yaml
version: 1
config:
  - type: physical
    name: eth0
    mac_address: "aa:bb:cc:dd:ee:ff"
    subnets:
      - type: static
        address: 10.0.0.51
        netmask: 255.255.255.0
        gateway: 10.0.0.1
        dns_nameservers:
          - 10.0.0.10
```

### Raw Image Decompression (Terraform bpg)

The bpg provider does not support `.xz` and Proxmox requires `.img` or `.iso` extension:
```bash
mv talos-nocloud.raw.xz talos-nocloud.img.xz
unxz talos-nocloud.img.xz
```

## Decision Points

### SMBIOS nocloud-net vs cicustom

| Aspect | SMBIOS nocloud-net | cicustom snippet |
|--------|-------------------|-----------------|
| **Config server** | HTTP server required | No external dependency |
| **Scale** | Excellent (3000+ proven) | Good (manual per-VM) |
| **Flexibility** | Dynamic config generation | Static file per VM |
| **Proxmox integration** | Requires `qm set` scripting | Native Proxmox feature |
| **Fleet-infra fit** | Overkill for 5-6 nodes | Better match |

**Recommendation for fleet-infra:** Use `cicustom` for small clusters (< 20 nodes). Use SMBIOS nocloud-net if building a self-service provisioning system or managing many clusters.

### Custom API vs Sidero Omni

JYSK lesson learned: consider whether a custom Go API outweighs Sidero Omni for your scale. Below ~100 clusters, Omni may be the better choice.

### nocloud ISO vs nocloud raw

| Format | Proxmox import | Terraform (bpg) | Notes |
|--------|---------------|----------------|-------|
| `nocloud-amd64.iso` | Native | Yes (content_type="iso") | Simpler |
| `nocloud-amd64.raw.xz` | Requires decompress | Yes (after rename) | Used for disk write |

### Versioning

Always match Talos image version and `talosctl` version. Mismatched versions (e.g., 1.6.x image + 1.7.x talosctl) cause config parsing errors.

## Known Issues

### First Boot Loop (v1.8.x)

- **Symptom:** `error running phase 6 in initialize sequence: unexpected EOF`
- **Cause:** Stray `META` partition label confuses Talos disk discovery
- **Fix v1.8.x:** Change SCSI controller: `scsi_hardware = "virtio-scsi-single"`
- **Fix permanent:** Upgrade to Talos v1.9.0+ (PR #9810)

## Lessons Learned (JYSK, 3000+ nodes)

1. Robust authentication is critical for config distribution
2. Securely storing and transferring encrypted data adds complexity -- plan key management before building the API
3. Plan for Day 2 operations (upgrades, cert rotation, node replacement) from the start
4. Talos team moves fast -- API must evolve in tandem (technical debt warning)
5. Line speeds vary -- config serving must be lightweight
6. Build in versioning of configuration files from the start
7. Consider if custom solution outweighs Sidero Omni for your scale

## References

- [Talos NoCloud Docs (v1.9)](https://docs.siderolabs.com/talos/v1.9/platform-specific-installations/cloud-platforms/nocloud/)
- [JYSK Tech: 3000 Clusters Part 3](https://jysk.tech/3000-clusters-part-3-how-to-boot-talos-linux-nodes-with-cloud-init-and-nocloud-acdce36f60c0) (Ryan Gough, Feb 6 2025)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Talos Image Factory](https://factory.talos.dev)
- [Talos Issue #9852 - First Boot](https://github.com/siderolabs/talos/issues/9852)
- [go-smbios library](https://github.com/digitalocean/go-smbios)
- [Sidero Omni](https://www.siderolabs.com/platform/saas-for-talos-linux/)
- Vault note: `~/notes/work/kubernetes/Talos NoCloud Boot - Proxmox Cloud-Init Provisioning.md`
