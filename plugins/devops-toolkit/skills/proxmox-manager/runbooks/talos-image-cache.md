---
name: talos-image-cache
description: Build Talos disk images with pre-cached container images to eliminate registry pulls at bootstrap
image_type: raw
requires: [talosctl, docker, ssh]
---

# Talos Image Cache

Build Talos disk images with container images pre-cached on-disk. At boot, a local `registryd` service serves images from the cache partition, eliminating external registry pulls during cluster bootstrap. This is critical for air-gapped environments, bandwidth-limited edge deployments, and large-scale rollouts where simultaneous registry pulls cause DDoS-like impact.

## Parameters

- talos_version: Talos release version, e.g. "1.9.5" (required)
- schematic_id: Image Factory schematic ID with extensions (required -- from `talos-image-factory.md`)
- extra_images_file: Path to a file listing additional container images to cache beyond Talos defaults (optional)
- image_disk_size: Disk size for the output image if cache is large (optional, e.g. "3GB")
- output_dir: Local directory for build artifacts (default: ./_out)

## Prerequisites

- `talosctl` CLI installed (matching target Talos version)
- `docker` running locally (used by the imager)
- Internet access to pull container images and `ghcr.io/siderolabs/imager`
- Schematic ID from Image Factory (see `talos-image-factory.md`)
- Know which additional images your cluster needs (Flux, Cilium, ExternalDNS, CSI drivers, etc.)

## Steps

1. **List default Talos images** (local)

   ```bash
   talosctl images default > images.txt
   ```

   Expected result: `images.txt` containing the default Talos system images (flannel, coredns, etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy, kubelet, installer, pause).

2. **Create extra images list** (local -- skip if no additional images needed)

   Create `extra-images.txt` with any additional container images the cluster needs. Include **both** tag-based and digest-based references for each image:

   ```
   ghcr.io/fluxcd/helm-controller:v1.1.0
   ghcr.io/fluxcd/helm-controller@sha256:4c75ca6c24ceb...
   ghcr.io/fluxcd/kustomize-controller:v1.4.0
   ghcr.io/fluxcd/kustomize-controller@sha256:e3b0cf847e9c...
   ghcr.io/fluxcd/source-controller:v1.4.1
   ghcr.io/fluxcd/source-controller@sha256:3c5f0f022f99...
   quay.io/cilium/cilium@sha256:d55ec38938854...
   quay.io/cilium/operator-generic@sha256:c55a7cbe19fe...
   ```

   **Important:** Both tag and digest references are required. The digest ensures the exact image layer is cached; the tag ensures Kubernetes manifests referencing by tag can resolve locally.

   Merge into the main list:

   ```bash
   cat extra-images.txt >> images.txt
   ```

   Expected result: `images.txt` contains all default Talos images plus your additional images.

3. **Create the OCI image cache** (local)

   ```bash
   cat images.txt | talosctl images cache-create --image-cache-path ./image-cache.oci --images=-
   ```

   Expected result: `image-cache.oci` directory created containing all cached container image layers in OCI format. This pulls every listed image, so it requires internet access and may take several minutes depending on image count and size.

4. **Build disk image with embedded cache** (local)

   ```bash
   mkdir -p <output_dir>
   docker run --rm -t \
     -v $PWD/<output_dir>:/secureboot:ro \
     -v $PWD/<output_dir>:/out \
     -v $PWD/image-cache.oci:/image-cache.oci:ro \
     -v /dev:/dev --privileged \
     ghcr.io/siderolabs/imager:v<talos_version> metal \
     --image-cache /image-cache.oci
   ```

   If the cache is large, extend the disk size:

   ```bash
   docker run --rm -t \
     -v $PWD/<output_dir>:/secureboot:ro \
     -v $PWD/<output_dir>:/out \
     -v $PWD/image-cache.oci:/image-cache.oci:ro \
     -v /dev:/dev --privileged \
     ghcr.io/siderolabs/imager:v<talos_version> metal \
     --image-cache /image-cache.oci \
     --image-disk-size=<image_disk_size>
   ```

   Expected result: ZST-compressed disk image in `<output_dir>/` containing the full Talos installation and cached images. This image replaces the standard nocloud image from Image Factory for template creation.

   **Note:** This uses the `metal` image type. For nocloud templates (PVE), the resulting image works the same way -- the cache is stored in a dedicated IMAGECACHE partition within the disk layout.

5. **Import as PVE template** (SSH)

   Follow `talos-template-create.md` using the cached disk image instead of the standard factory image. The only difference is the image source -- use the local ZST file instead of downloading from `factory.talos.dev`:

   ```bash
   # Copy to node (the image is ZST-compressed, not XZ)
   scp <output_dir>/metal-amd64.raw.zst <SSH_USER>@<NODE_HOST>:/tmp/<template_name>.raw.zst

   # Decompress on node
   ssh <SSH_USER>@<NODE_HOST> 'zstd -d /tmp/<template_name>.raw.zst -o /tmp/<template_name>.raw'
   ```

   Then continue with `talos-template-create.md` from step 5 (create VM shell) onward, using `/tmp/<template_name>.raw` as the import source.

6. **Enable image cache in machine config** (local)

   When generating machine configs or creating per-node patches, include the image cache feature flag. Add this to the base config patch or per-node patches:

   ```yaml
   machine:
     features:
       imageCache:
         localEnabled: true
   ```

   Or as a `talosctl gen config` patch:

   ```bash
   talosctl gen config <CLUSTER_NAME> https://<API_ENDPOINT>:6443 \
     --output-dir <config_dir> \
     --with-secrets <config_dir>/<secrets_file> \
     --install-image "$INSTALLER" \
     --config-patch '[
       {"op": "add", "path": "/machine/features/imageCache", "value": {"localEnabled": true}}
     ]'
   ```

   **Critical:** This must be enabled BEFORE bootstrap. If the image cache feature is not enabled in the machine config, Talos will automatically remove the IMAGECACHE partition on first boot.

7. **Bootstrap and verify** (local)

   After applying configs and bootstrapping (per `talos-cluster-bootstrap.md`), verify the cache is active:

   **Check IMAGECACHE partition exists:**

   ```bash
   talosctl get discoveredvolumes --nodes <node_ip> | grep IMAGECACHE
   ```

   Expected result: A partition with label `IMAGECACHE` (typically ext4, ~2-3 GB depending on cache size).

   **Check registryd service is running:**

   ```bash
   talosctl get services --nodes <node_ip> | grep registryd
   ```

   Expected result: `registryd` service with `RUNNING=true` and `HEALTHY=true`.

   **Verify images are served locally:**

   ```bash
   talosctl logs registryd --nodes <node_ip> | head -20
   ```

   Expected result: Log entries showing image requests with `remote_addr: 127.0.0.1`, confirming images are pulled from the local registryd service rather than external registries.

## Cleanup

- Remove local build artifacts: `rm -rf image-cache.oci images.txt extra-images.txt`
- Remove images from PVE node: `ssh <SSH_USER>@<NODE_HOST> 'rm -f /tmp/<template_name>.raw /tmp/<template_name>.raw.zst'`

## Notes

- **When to use image cache:** Air-gapped environments, bandwidth-limited edge locations, or large-scale deployments (100+ clusters) where simultaneous registry pulls create unacceptable load on the registry.
- **Dual references required:** Extra images must include both tag-based (`image:v1.0.0`) and digest-based (`image@sha256:abc...`) references. This ensures both resolution methods work from the local cache.
- **Cache scope:** The cache is per-node, embedded in the disk image. Every VM cloned from the cached template has its own local cache. No shared registry infrastructure is needed.
- **registryd service:** Talos runs a local `registryd` service bound to `127.0.0.1` that intercepts container image pulls and serves them from the IMAGECACHE partition. This is transparent to kubelet and containerd.
- **Cache updates:** To update cached images (e.g., for a Kubernetes version bump), rebuild the cache and create a new template. Existing VMs retain their original cache.
- **Packer integration:** For automated template pipelines, the cache creation can be incorporated into a Packer build. Create the cache, then use the imager to produce the disk image, and feed it into Packer as the base image.
- **Disk sizing:** Default disk size may not accommodate large caches. Use `--image-disk-size` to increase. Monitor the IMAGECACHE partition size after deployment to right-size future builds.
- **Compression:** The imager outputs ZST-compressed images (not XZ like factory images). Use `zstd -d` instead of `xz -d` when decompressing on the PVE node.
