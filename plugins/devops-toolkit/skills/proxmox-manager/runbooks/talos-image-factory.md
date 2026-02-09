---
name: talos-image-factory
description: Build custom Talos Linux images with extensions via factory.talos.dev
image_type: raw
requires: [curl, jq]
---

# Talos Image Factory

## Parameters

- talos_version: Talos release version, e.g. "1.9.0" (required)
- extensions: List of Talos system extensions to include (default: ["siderolabs/qemu-guest-agent"])
- image_type: Image type to download -- "nocloud" for templates, "metal" for bare-metal (default: nocloud)
- arch: CPU architecture (default: amd64)
- output_dir: Local directory to save downloaded image (default: /tmp)

## Prerequisites

- `curl` and `jq` installed locally
- Internet access to `factory.talos.dev`
- Know which Talos version and extensions you need (see extension discovery below)

## Steps

1. **Discover available Talos versions** (local)

   ```bash
   curl -sL https://factory.talos.dev/versions | jq -r '.[]' | head -20
   ```

   Expected result: List of available Talos release versions (e.g., `v1.9.0`, `v1.8.4`).

2. **List available extensions for a version** (local)

   ```bash
   curl -sL "https://factory.talos.dev/v1/overlays?talos_version=v<talos_version>" | jq -r '.[].name'
   curl -sL "https://factory.talos.dev/v1/extensions?talos_version=v<talos_version>" | jq -r '.[].name'
   ```

   Expected result: List of extension names (e.g., `siderolabs/qemu-guest-agent`, `siderolabs/iscsi-tools`).

3. **Create a schematic with desired extensions** (local)

   Build a schematic JSON payload listing the extensions to bake into the image:

   ```bash
   SCHEMATIC=$(curl -sL -X POST https://factory.talos.dev/schematics \
     -H "Content-Type: application/json" \
     -d '{
       "customization": {
         "systemExtensions": {
           "officialExtensions": [
             "siderolabs/qemu-guest-agent",
             "siderolabs/iscsi-tools"
           ]
         }
       }
     }' | jq -r '.id')
   echo "Schematic ID: $SCHEMATIC"
   ```

   Expected result: A 64-character hex schematic ID. Save this ID -- it encodes your exact extension set and is deterministic (same input always yields the same ID).

4. **Download the nocloud image for PVE templates** (local)

   ```bash
   curl -sLo <output_dir>/talos-<talos_version>-nocloud-<arch>.raw.xz \
     "https://factory.talos.dev/image/$SCHEMATIC/v<talos_version>/nocloud-<arch>.raw.xz"
   ```

   Expected result: Compressed raw disk image at the output path. File size is typically 80-120 MB compressed.

5. **Download the installer image for upgrades** (local)

   The installer image is used with `talosctl upgrade --image`. It is a container image reference, not a file download:

   ```
   factory.talos.dev/installer/$SCHEMATIC:v<talos_version>
   ```

   This URL is passed directly to `talosctl upgrade --image` -- no download needed.

6. **Record the schematic in the cluster profile** (local)

   Update the cluster profile's `talos.factory.schematic_id` field with the generated ID:

   ```yaml
   talos:
     factory:
       schematic_id: "<SCHEMATIC_ID>"
       extensions:
         - siderolabs/qemu-guest-agent
         - siderolabs/iscsi-tools
   ```

   This ensures the image build is reproducible and the correct installer image is used for upgrades.

## Cleanup

- Remove downloaded images from `<output_dir>` after importing into PVE template
- Schematic IDs are permanent and cached by the factory -- no cleanup needed

## Notes

- **Required extension for PVE:** `siderolabs/qemu-guest-agent` is mandatory for Proxmox integration. Without it, the guest agent is unavailable and PVE cannot perform graceful shutdown or IP reporting.
- **Optional extensions:**
  - `siderolabs/iscsi-tools` -- required for iSCSI-based CSI drivers (e.g., democratic-csi, Longhorn iSCSI)
  - `siderolabs/util-linux-tools` -- provides `lsblk` and other utilities
  - `siderolabs/tailscale` -- Tailscale VPN integration
- **Schematic determinism:** The same set of extensions always produces the same schematic ID. You do not need to re-create schematics unless changing extensions.
- **Version pinning:** Always use the full version string (e.g., `v1.9.0`, not `v1.9`) in factory URLs. The factory requires exact version matches.
- **Image types:**
  - `nocloud` -- for cloud environments without a metadata service (PVE without cloud-init). Talos configures itself via machine config applied through `talosctl`.
  - `metal` -- for bare-metal installations. Boots into maintenance mode waiting for a machine config.
  - Both types work with PVE, but `nocloud` is preferred for template-based provisioning.
