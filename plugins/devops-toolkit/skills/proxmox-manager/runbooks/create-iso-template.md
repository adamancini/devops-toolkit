---
name: create-iso-template
description: Create a VM template from an ISO installer with manual OS installation
image_type: iso
requires: [api, ssh]
---

# Create ISO-Based VM Template

## Parameters

- iso_url: URL of the ISO to download (required, unless iso_path provided)
- iso_path: Existing ISO path on node storage, e.g. local:iso/ubuntu-24.04.iso (optional -- skips download)
- template_name: Name for the template VM (required)
- vmid: Template VMID (default: next available in vmid_ranges.templates)
- node: Target Proxmox node (default: pve01)
- storage: Storage backend for disks (default: local-lvm)
- cores: CPU cores (default: 2)
- memory: Memory in MB (default: 2048)
- disk_size: Primary disk size (default: 32G)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- SSH access to the target node as `credentials.ssh_user`
- Access to the Proxmox web console for the manual installation step

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

3. **Download ISO to node storage** (SSH) -- skip if `iso_path` provided
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /var/lib/vz/template/iso/<template_name>.iso <iso_url>'
   ```
   Expected result: ISO at `/var/lib/vz/template/iso/<template_name>.iso`. Set `iso_path` to `local:iso/<template_name>.iso` for subsequent steps.

4. **Create VM with primary disk, EFI disk, and ISO attached** (SSH)
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
     --ostype l26 \
     --efidisk0 <storage>:0,efitype=4m,pre-enrolled-keys=0 \
     --scsi0 <storage>:<disk_size> \
     --ide2 <iso_path>,media=cdrom \
     --boot order=ide2;scsi0'
   ```
   Expected result: VM created with a blank primary disk on scsi0, EFI vars disk, and the ISO mounted on ide2. Boot order is set to IDE first (installer), then scsi0.

   > **Note:** ide2 for the ISO is appropriate here. Unlike the cloud-init drive issue, the installer runs after UEFI firmware has fully initialized all devices. The scsi1 requirement is specific to cloud-init's early-boot config read behavior.

5. **Start VM for installation** (API)
   ```bash
   curl -sk -X POST \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<node>/qemu/<vmid>/status/start"
   ```
   Expected result: VM starts and boots from the ISO installer.

6. **MANUAL: Complete OS installation** (User action)

   Open the Proxmox web console at `https://<NODE_HOST>:8006` and connect to the VM's VNC/SPICE console. During installation:

   - Install the OS to the scsi0 disk
   - Install the QEMU guest agent (`qemu-guest-agent` package)
   - Enable and start the guest agent service
   - Configure SSH server and create the desired user account
   - (Optional) Install cloud-init if post-clone customization is desired
   - Shut down the VM when installation is complete

   **Wait for the user to confirm installation is complete before proceeding.**

7. **Wait for VM to stop** (API)
   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/nodes/<node>/qemu/<vmid>/status/current" \
     | jq '.data.status'
   ```
   Poll until status is `"stopped"`. The user should shut down the VM from within the guest OS after completing installation.

8. **Detach ISO** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --ide2 none,media=cdrom'
   ```
   Expected result: ISO unmounted from ide2. The CD-ROM device remains but is empty.

9. **Set boot order to scsi0 only** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --boot order=scsi0'
   ```
   Expected result: VM boots directly from the installed OS disk.

10. **Apply tag** (SSH)
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --tags template'
    ```
    Expected result: VM tagged with `template`.

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
      | jq '{template: .data.template, tags: .data.tags, name: .data.name, scsi0: .data.scsi0, ide2: .data.ide2, boot: .data.boot}'
    ```
    Expected result: `template: 1`, tag `template`, scsi0 is the installed disk, ide2 is empty cdrom, boot order is scsi0.

## Cleanup

- Optionally remove the downloaded ISO: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /var/lib/vz/template/iso/<template_name>.iso'`
- Keep the ISO if you plan to create more templates from it

## Notes

- This runbook requires manual interaction via the Proxmox web console for OS installation. It cannot be fully automated.
- Install the QEMU guest agent during OS setup -- it enables graceful shutdown, IP address reporting, and filesystem freeze for snapshots.
- If the guest OS supports cloud-init, install it during setup to enable post-clone customization (user, SSH keys, network) without needing to log into each clone.
- For Windows templates, use `ostype=win11` (or appropriate version), add a VirtIO driver ISO on a second CD-ROM, and install the VirtIO drivers during Windows setup.
