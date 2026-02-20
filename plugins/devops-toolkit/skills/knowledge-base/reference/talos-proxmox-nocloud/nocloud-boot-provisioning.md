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

Talos Linux supports a `nocloud` cloud-init datasource for automated VM configuration injection at boot. Two modes exist: SMBIOS serial (network-based HTTP config fetch) and CDROM/ISO (local storage). SMBIOS-based nocloud-net is the scalable pattern -- JYSK used it to provision 3,000+ store clusters by encoding a per-VM config-server URL in the Proxmox SMBIOS serial field via `qm set`. The `nocloud` image variant from factory.talos.dev must be used (not `metal`).

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

Talos reads this at boot via `go-smbios` and fetches:
- `<url>/user-data` - Talos machine configuration YAML (required)
- `<url>/meta-data` - Hostname: `local-hostname: <name>` (optional)
- `<url>/network-config` - Cloud-init v1 network format (optional)

Requires DHCP network connectivity at first boot.

### Datasource Mode 2: CDROM/ISO (local)

Filesystem labeled `cidata` or `CIDATA` (VFAT or ISO9660) containing the same files. No network required at boot.

ISO creation:
```bash
genisoimage -output cidata.iso -V cidata -r -J user-data meta-data network-config
```

## Practical Application

### Proxmox SMBIOS Configuration (CLI)

The serial field must be base64-encoded when set via CLI. Always preserve the existing UUID.

```bash
# Build the nocloud-net spec
SMBIOSSERIAL="ds=nocloud-net;s=http://10.10.0.1/configs/node1/;h=node1"

# Encode
NEW_SERIAL=$(printf '%s' "${SMBIOSSERIAL}" | base64)

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

### QEMU (non-Proxmox)

```bash
qemu-system-x86_64 -smbios type=1,serial=ds=nocloud-net;s=http://10.10.0.1/configs/
```

### Proxmox cicustom (snippet-based)

Alternative to SMBIOS -- attach Talos machine config directly as cloud-init user-data:

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

### JYSK Scale Pattern (3000+ clusters)

Per-store automation script run on Proxmox hosts:
```bash
VMID=$1
STORE_ID=$2
SMBIOSSERIAL="ds=nocloud-net;s=http://api.domain.com/store/${STORE_ID}/;h=talos-${STORE_ID}"
NEW_SERIAL=$(printf '%s' "${SMBIOSSERIAL}" | base64)
UUID=$(qm config ${VMID} | grep smbios1 | grep -oP 'uuid=\K[^,]+')
/usr/sbin/qm set ${VMID} --smbios1 uuid=${UUID},serial=${NEW_SERIAL},base64=1
```

Each store VM gets a unique URL pointing to a central config API that returns per-store Talos machine configs.

### Raw Image Decompression (Terraform bpg)

The bpg provider doesn't support `.xz` and Proxmox requires `.img` or `.iso` extension:
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

## References

- [Talos NoCloud Docs (v1.9)](https://docs.siderolabs.com/talos/v1.9/platform-specific-installations/cloud-platforms/nocloud/)
- [JYSK Tech: 3000 Clusters Part 3](https://jysk.tech/3000-clusters-part-3-how-to-boot-talos-linux-nodes-with-cloud-init-and-nocloud-acdce36f60c0)
- [Proxmox Cloud-Init Support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [Talos Image Factory](https://factory.talos.dev)
- [Talos Issue #9852 - First Boot](https://github.com/siderolabs/talos/issues/9852)
- Vault note: `~/notes/work/kubernetes/Talos NoCloud Boot - Proxmox Cloud-Init Provisioning.md`
