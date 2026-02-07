---
name: create-cloudinit-template
description: Create a VM template from a cloud-init enabled disk image
image_type: cloudinit
requires: [api, ssh]
---

# Create Cloud-Init VM Template

## Parameters

- image_url: URL of the cloud image to download (required)
- template_name: Name for the template VM (required)
- vmid: Template VMID (default: next available in vmid_ranges.templates)
- node: Target Proxmox node (default: pve01)
- storage: Storage backend for disks (default: local-lvm)
- cores: CPU cores (default: 2)
- memory: Memory in MB (default: 2048)
- disk_size: Final disk size, e.g. 32G (optional -- only if larger than the source image)
- ciuser: Cloud-init default user (default: ada)
- sshkeys: Path to authorized_keys file (default: ~/.ssh/authorized_keys)

## Prerequisites

- API credentials configured in `pass` at `credentials.pass_path`
- SSH access to the target node as `credentials.ssh_user`
- The cloud image URL must be publicly accessible (or accessible from the node)

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
   Pick the next unused ID within `vmid_ranges.templates` (100-999). If a specific `vmid` parameter was provided, verify it is not already in use.

3. **Download cloud image to node** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'wget -q -O /tmp/<template_name>.img <image_url>'
   ```
   Expected result: Image file at `/tmp/<template_name>.img` on the node. For large images, this may take a moment.

4. **Create VM with cluster defaults** (SSH)
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
     --serial0 socket \
     --vga serial0 \
     --ostype l26'
   ```
   Expected result: VM `<vmid>` created with no disks attached. The serial console (`serial0 socket` + `vga serial0`) enables `qm terminal` access for debugging cloud-init.

5. **Add EFI disk** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --efidisk0 <storage>:0,efitype=4m,pre-enrolled-keys=0'
   ```
   Expected result: A 4 MB EFI vars disk created on the target storage. `pre-enrolled-keys=0` per cluster config.

6. **Import cloud image as scsi0** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --scsi0 <storage>:0,import-from=/tmp/<template_name>.img,discard=on,iothread=1,ssd=1'
   ```
   Expected result: The cloud image is imported into the storage backend and attached as `scsi0` in one atomic step. The `import-from` syntax (PVE 8.x+) replaces the legacy `qm importdisk` workflow.

   > **Legacy alternative:** On PVE < 8.0, use `qm importdisk <vmid> /tmp/<template_name>.img <storage>` followed by `qm set <vmid> --scsi0 <storage>:vm-<vmid>-disk-1,discard=on,iothread=1,ssd=1`. The legacy path requires parsing `unused0` from the config to find the disk name.

7. **Grow disk** (SSH) -- skip if `disk_size` not provided
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm disk resize <vmid> scsi0 <disk_size>'
   ```
   Expected result: `scsi0` resized to `<disk_size>`. Cloud images are typically 2-3 GB; growing to 32G+ is common.

8. **Add cloud-init drive on scsi1** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
     --scsi1 <storage>:cloudinit'
   ```
   Expected result: A cloud-init config drive attached as `scsi1`.

   > **Why scsi1, not ide2?** IDE devices are not available early enough during OVMF cold boot for cloud-init to read its config. Using scsi1 avoids this known issue with UEFI firmware.

9. **Set boot order to scsi0** (SSH)
   ```bash
   ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --boot order=scsi0'
   ```
   Expected result: VM boots from the imported cloud image disk.

10. **Configure cloud-init settings** (SSH)

    First, copy the SSH public keys to the node:
    ```bash
    scp <sshkeys> <SSH_USER>@<NODE_HOST>:/tmp/<template_name>-sshkeys.pub
    ```

    Then configure cloud-init:
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> \
      --ciuser <ciuser> \
      --sshkeys /tmp/<template_name>-sshkeys.pub \
      --ipconfig0 ip=dhcp'
    ```
    Expected result: Cloud-init configured with the default user, SSH keys, and DHCP networking. The `--sshkeys` flag expects a file path on the node, hence the `scp` step.

11. **Apply tags** (SSH)
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm set <vmid> --tags template,cloudinit'
    ```
    Expected result: VM tagged with `template` and `cloudinit` for easy filtering.

12. **Convert to template** (SSH)
    ```bash
    ssh <SSH_USER>@<NODE_HOST> 'qm template <vmid>'
    ```
    Expected result: VM converted to an immutable template. No REST API equivalent exists for this operation.

13. **Verify template** (API)
    ```bash
    curl -sk \
      -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
      "https://<NODE_HOST>:8006/api2/json/nodes/<node>/qemu/<vmid>/config" \
      | jq '{template: .data.template, tags: .data.tags, name: .data.name, scsi0: .data.scsi0, scsi1: .data.scsi1, boot: .data.boot}'
    ```
    Expected result: `template: 1`, tags include `template;cloudinit`, scsi0 is the imported disk, scsi1 is the cloud-init drive.

## Cleanup

- Remove downloaded image: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /tmp/<template_name>.img'`
- Remove temporary SSH keys file: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /tmp/<template_name>-sshkeys.pub'`

## Notes

- Cloud images are pre-configured for cloud-init but may not include the QEMU guest agent. Ubuntu noble (24.04) does **not** ship `qemu-guest-agent` in its cloud image. To enable guest agent features (IP reporting, graceful shutdown, filesystem freeze), install it via a cloud-init vendor snippet or `runcmd`: `apt-get install -y qemu-guest-agent && systemctl enable --now qemu-guest-agent`.
- The serial console configuration (`serial0 socket` + `vga serial0`) enables `qm terminal <vmid>` for debugging cloud-init issues without VNC.
- To clone from this template, use `POST /nodes/<node>/qemu/<vmid>/clone` with `full=1` and supply cloud-init overrides (ciuser, sshkeys, ipconfig0) on the clone.
- Common cloud images: Ubuntu (`noble-server-cloudimg-amd64.img`), Debian (`debian-12-generic-amd64.qcow2`), Fedora (`Fedora-Cloud-Base-*.qcow2`), Rocky (`Rocky-*-GenericCloud.qcow2`).
