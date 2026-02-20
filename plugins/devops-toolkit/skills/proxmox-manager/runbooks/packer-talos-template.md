---
name: packer-talos-template
description: Create Talos PVE templates using HashiCorp Packer and Image Factory API (CI/CD-friendly alternative to SSH-based creation)
image_type: raw
requires: [packer, curl]
---

# Packer-Based Talos Template Creation

An alternative to the SSH-based `talos-template-create.md` runbook. Uses HashiCorp Packer to automate template creation entirely through the Proxmox API -- no SSH access to hypervisor nodes required. Packer boots a live Arch Linux ISO, downloads the Talos image from Image Factory, writes it to disk, and converts the VM to a template.

## Parameters

- talos_version: Talos release version, e.g. "v1.9.2" (required)
- extensions: List of Talos system extensions (default: ["siderolabs/qemu-guest-agent"])
- template_name: Template name pattern (default: `talos-template-${talos_version}-qemu`)
- node: Target Proxmox node (required)
- storage: Storage backend for VM disks (default from cluster-config)
- static_ip: Temporary static IP for the Arch live VM with CIDR (required, e.g. "10.0.30.163/25")
- gateway: Gateway for the Arch live VM (required)
- arch_iso: Arch Linux ISO on PVE storage (default: "local:iso/archlinux-x86_64.iso")

## Prerequisites

- `packer` CLI installed locally (with `proxmox` plugin >= 1.1.7)
- Arch Linux live ISO uploaded to PVE node storage (or use `iso_url` for auto-download)
- PVE API token with VM provisioning privileges (same token from `credentials.pass_path`)
- Temporary static IP available on the VM network for the build process
- Internet access from the VM network to `factory.talos.dev`

## Project Structure

Create a directory with these files:

```
talos_packer/
  proxmox.pkr.hcl
  variables.pkr.hcl
  vars/
    local.pkrvars.hcl
  files/
    schematic.yaml
```

## Steps

1. **Initialize Packer plugins** (local)

   ```bash
   cd talos_packer
   packer init .
   ```

   Expected result: Proxmox plugin downloaded and initialized.

2. **Create schematic file** (local)

   Create `files/schematic.yaml` with desired extensions:

   ```yaml
   customization:
     systemExtensions:
       officialExtensions:
         - siderolabs/qemu-guest-agent
   ```

   Add additional extensions as needed (e.g., `siderolabs/iscsi-tools`).

3. **Create variables file** (local)

   Create `vars/local.pkrvars.hcl`:

   ```hcl
   proxmox_storage      = "local-lvm"
   proxmox_storage_type = "raw"
   talos_version        = "v1.9.2"
   static_ip            = "<STATIC_IP>/24"
   gateway              = "<GATEWAY>"
   ```

4. **Create the Packer build definition** (local)

   Create `variables.pkr.hcl` and `proxmox.pkr.hcl` per the reference at `knowledge-base/reference/packer-talos-proxmox/packer-talos-image-factory.md`.

   Key adaptations for cluster conventions:
   - Set `bios = "ovmf"` (Talos requires UEFI)
   - Add an EFI disk configuration
   - Use `virtio-scsi-single` as the SCSI controller (cluster default)
   - Set `format = "raw"` for LVM-thin storage
   - Enable `qemu_agent = true`
   - Tag with `template;talos` to match existing conventions

5. **Run the build** (local)

   ```bash
   packer build -on-error=ask \
     -var-file="vars/local.pkrvars.hcl" \
     -var proxmox_username="$(pass show <PASS_PATH> | head -1)" \
     -var proxmox_token="$(pass show <PASS_PATH> | tail -1)" \
     -var proxmox_nodename="<NODE_NAME>" \
     -var proxmox_url="https://<NODE_HOST>:8006/api2/json" .
   ```

   Expected result: Packer creates the VM, boots Arch, downloads and writes the Talos image, shuts down, and converts to template. Duration depends on network speed to factory API.

6. **Verify template** (API)

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '.data[] | select(.template == 1) | select(.tags // "" | test("talos")) | {vmid, name, tags}'
   ```

   Expected result: New template visible with `talos` tag and version in the name.

## Cleanup

- Packer handles VM cleanup on failure when using `-on-error=ask` (prompts for action) or `-on-error=cleanup` (auto-cleanup)
- The Arch ISO remains on PVE storage for future builds
- Old templates from previous versions can be deleted once new clones are verified

## Notes

- **UEFI adaptation required:** The original article uses SeaBIOS. For Talos, add `bios = "ovmf"` and an EFI disk to the Packer source block. Without UEFI, Talos will not boot.
- **VMID allocation:** Packer auto-assigns VMIDs unless you specify `vm_id` in the source block. To control VMID allocation within `vmid_ranges.templates`, set `vm_id` explicitly.
- **Credential security:** Pass API token via `-var` flags with `$(pass show ...)` substitution. Never set tokens as persistent environment variables or commit them to the Packer variable files.
- **Proxy environments:** Add proxy environment variables to the shell provisioner if the VM network requires a proxy to reach `factory.talos.dev`.
- **Dual disks:** The article creates two disks (OS + local storage). Adapt disk count and sizes to match cluster profile requirements.
- **CI/CD integration:** This approach is designed for pipeline automation. The same build can be triggered on new Talos version releases to automatically create updated templates.
- **Comparison with SSH approach:** Use this for automated pipelines and environments without hypervisor SSH. Use `talos-template-create.md` for simpler one-off creation with direct node access.
