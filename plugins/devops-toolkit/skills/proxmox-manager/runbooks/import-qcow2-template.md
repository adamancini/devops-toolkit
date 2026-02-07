---
name: import-qcow2-template
description: Create a VM template by importing a pre-built qcow2 or raw disk image
image_type: qcow2
requires: [api, ssh]
---

# Import qcow2/raw Disk Image as Template

## Parameters

- image_url: URL of the disk image to download (required)
- image_format: Disk image format (default: qcow2 -- also accepts raw)
- template_name: Name for the template VM (required)
- vmid: Template VMID (default: next available in vmid_ranges.templates)
- node: Target Proxmox node (default: pve01)
- storage: Storage backend for disks (default: local-lvm)
- cores: CPU cores (default: 2)
- memory: Memory in MB (default: 2048)
- disk_size: Final disk size, e.g. 32G (optional -- only if larger than the source image)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- SSH access to the target node as `credentials.ssh_user`
- The disk image URL must be accessible from the node

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

3. **Download disk image to node** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /tmp/<template_name>.<image_format> <image_url>'
   ```
   Expected result: Disk image at `/tmp/<template_name>.<image_format>` on the node.

4. **Create VM shell with cluster defaults** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm create <vmid> \
     --name <template_name> \
     --bios ovmf \
     --machine q35 \
     --cpu host \
     --cores <cores> \
     --memory <memory> \
     --scsihw virtio-scsi-single \
     --net0 virtio,bridge=vmbr0 \
     --agent enabled=1 \
     --ostype l26'
   ```
   Expected result: Empty VM created with cluster-standard hardware configuration.

5. **Add EFI disk** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --efidisk0 <storage>:0,efitype=4m,pre-enrolled-keys=0'
   ```
   Expected result: 4 MB EFI vars disk created.

6. **Import disk image as scsi0** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --scsi0 <storage>:0,import-from=/tmp/<template_name>.<image_format>,discard=on,iothread=1,ssd=1'
   ```
   Expected result: Disk image imported and attached as scsi0. The `import-from` syntax (PVE 8.x+) handles both qcow2 and raw formats automatically -- Proxmox detects the format and converts to the storage backend's native format (e.g., raw for LVM-thin).

   > **Legacy alternative:** On PVE < 8.0, use `qm importdisk <vmid> /tmp/<template_name>.<image_format> <storage>` followed by `qm set <vmid> --scsi0 <storage>:vm-<vmid>-disk-1,discard=on,iothread=1,ssd=1`.

7. **Grow disk** (SSH) -- skip if `disk_size` not provided
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm disk resize <vmid> scsi0 <disk_size>'
   ```
   Expected result: scsi0 resized to `<disk_size>`.

8. **Set boot order to scsi0** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --boot order=scsi0'
   ```
   Expected result: VM boots from the imported disk.

9. **Apply tag** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --tags template'
   ```
   Expected result: VM tagged with `template`.

10. **Convert to template** (SSH)
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm template <vmid>'
    ```
    Expected result: VM converted to an immutable template.

11. **Verify template** (API)
    ```bash
    curl -sk \
      -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
      "https://<NODE_HOST>:8006/api2/json/nodes/<node>/qemu/<vmid>/config" \
      | jq '{template: .data.template, tags: .data.tags, name: .data.name, scsi0: .data.scsi0, boot: .data.boot}'
    ```
    Expected result: `template: 1`, tag `template`, scsi0 is the imported disk.

## Cleanup

- Remove downloaded image: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /tmp/<template_name>.<image_format>'`

## Notes

- This runbook does **not** configure cloud-init. The imported image boots as-is. Post-clone customization requires manual configuration, Ansible, or another provisioning tool.
- For Talos Linux raw images (e.g., `metal-amd64.raw.xz`), decompress first (`xz -d`) then import with `image_format: raw`. Talos images are fully self-configuring via their machine config -- no cloud-init needed.
- For images that include cloud-init support, use the `create-cloudinit-template` runbook instead to get proper cloud-init drive and configuration.
- The `import-from` syntax auto-detects the source format. You do not need to specify qcow2 vs raw explicitly -- Proxmox reads the image header.
