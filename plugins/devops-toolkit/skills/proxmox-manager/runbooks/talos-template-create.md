---
name: talos-template-create
description: Create a PVE VM template from a Talos Linux nocloud image with baked-in extensions
image_type: raw
requires: [api, ssh]
tested_with:
  talos: "1.9.x"
  kubernetes: "1.32.x"
  proxmox: "8.x"
---

# Create PVE Template from Talos Image

## Parameters

- image_url: URL of the Talos nocloud image from Image Factory (required, e.g. `https://factory.talos.dev/image/<SCHEMATIC>/v1.9.0/nocloud-amd64.raw.xz`)
- template_name: Name for the template VM (required, e.g. `talos-1.9.0`)
- vmid: Template VMID (default: next available in vmid_ranges.templates)
- node: Target Proxmox node for the template (default: pve01)
- storage: Storage backend for disks (default: local-lvm)
- disk_size: Final disk size after import (optional, e.g. 10G -- only needed if growing beyond the default ~1.5G Talos image)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- SSH access to the target node as `credentials.ssh_user`
- Talos nocloud image URL from Image Factory (see `talos-image-factory.md` runbook)
- `xz` available on the PVE node (standard on Debian/PVE)

## Steps

1. **Verify API connectivity** (API)

   ```bash
   curl -sk -o /dev/null -w "%{http_code}" \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     https://<NODE_HOST>:8006/api2/json/version
   ```

   Expected result: `200`

2. **Allocate VMID in template range** (API)

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '[.data[].vmid] | sort'
   ```

   Pick the next unused ID within `vmid_ranges.templates` (100-999).

3. **Download Talos nocloud image to node** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /tmp/<template_name>.raw.xz <image_url>'
   ```

   Expected result: Compressed image at `/tmp/<template_name>.raw.xz` on the node.

4. **Decompress the image** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'xz -d /tmp/<template_name>.raw.xz'
   ```

   Expected result: Decompressed raw image at `/tmp/<template_name>.raw`. The `.raw.xz` file is removed by `xz -d`.

5. **Create VM shell with cluster defaults** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm create <vmid> \
     --name <template_name> \
     --bios ovmf \
     --machine q35 \
     --cpu host \
     --cores 2 \
     --memory 2048 \
     --scsihw virtio-scsi-single \
     --net0 virtio,bridge=vmbr0 \
     --agent enabled=1 \
     --ostype l26'
   ```

   Expected result: Empty VM created with cluster-standard hardware configuration. Cores and memory are template defaults -- they will be overridden when cloning for actual use.

   **Note:** No cloud-init drive is added. Talos images are self-configuring via machine config applied through `talosctl apply-config`. Cloud-init is not used.

6. **Add EFI disk** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --efidisk0 <storage>:0,efitype=4m,pre-enrolled-keys=0'
   ```

   Expected result: 4 MB EFI vars disk created. UEFI boot is required for Talos.

7. **Import raw disk as scsi0** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --scsi0 <storage>:0,import-from=/tmp/<template_name>.raw,discard=on,iothread=1,ssd=1'
   ```

   Expected result: Talos disk image imported and attached as scsi0. The `import-from` syntax handles raw format automatically.

8. **Grow disk** (SSH) -- skip if `disk_size` not provided

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm disk resize <vmid> scsi0 <disk_size>'
   ```

   Expected result: scsi0 resized to `<disk_size>`. Talos uses the full disk automatically on boot.

9. **Set boot order** (SSH)

   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --boot order=scsi0'
   ```

   Expected result: VM boots from the imported Talos disk.

10. **Apply tags** (SSH)

    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --tags "template;talos"'
    ```

    Expected result: VM tagged with `template` and `talos` for identification.

11. **Convert to template** (SSH)

    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm template <vmid>'
    ```

    Expected result: VM converted to an immutable template.

12. **Verify template** (API)

    ```bash
    curl -sk \
      -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
      "https://<NODE_HOST>:8006/api2/json/nodes/<node>/qemu/<vmid>/config" \
      | jq '{template: .data.template, tags: .data.tags, name: .data.name, scsi0: .data.scsi0, boot: .data.boot, bios: .data.bios}'
    ```

    Expected result: `template: 1`, tags include `template;talos`, scsi0 is the imported disk, bios is `ovmf`.

## Cleanup

- Remove downloaded image: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /tmp/<template_name>.raw /tmp/<template_name>.raw.xz'`

## Notes

- **No cloud-init:** Talos images do not use cloud-init. Configuration is applied via `talosctl apply-config` after VMs are cloned and started. Do not add a cloud-init drive (`ide2` or `scsi1`) to the template.
- **UEFI required:** Talos requires UEFI boot (`bios: ovmf`). Legacy BIOS is not supported.
- **Extensions are baked in:** The Talos image from Image Factory already contains the selected extensions (e.g., `qemu-guest-agent`). Extensions cannot be added at runtime -- a new image must be built.
- **Template sizing:** The template's cores and memory are defaults that get overridden during cloning. Keep them small (2 cores, 2048 MB) to avoid confusion.
- **Disk size:** The Talos nocloud image is ~1.5 GB. For production use, grow the disk at clone time (via the cluster profile's `disk` field) rather than in the template.
- This runbook is Talos-specific. For generic cloud images with cloud-init, use `create-cloudinit-template.md`. For raw/qcow2 images without cloud-init, use `import-qcow2-template.md`.
