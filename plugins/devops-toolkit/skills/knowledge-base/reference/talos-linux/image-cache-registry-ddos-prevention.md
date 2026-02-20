---
topic: talos-linux
source: https://jysk.tech/3000-clusters-part-4-how-not-to-ddos-your-internal-registry-b230fc596159
created: 2026-02-20
updated: 2026-02-20
tags:
  - talos
  - image-cache
  - registryd
  - air-gapped
  - large-scale
  - registry
---

# Talos Image Cache: Preventing Registry DDoS at Scale

## Summary

Talos Linux's local image cache embeds container images into the node's disk image via a dedicated IMAGECACHE partition. A local `registryd` service serves images from this partition on `127.0.0.1`, eliminating external registry pulls during bootstrap. Designed for air-gapped environments, bandwidth-limited edge, and large-scale deployments (3000+ clusters) where simultaneous pulls overwhelm registries.

## Key Concepts

### Architecture

- **IMAGECACHE partition:** Dedicated ext4 partition in the Talos disk layout containing OCI image layers
- **registryd service:** Talos system service that acts as a local registry proxy on `127.0.0.1`, transparently serving cached images to containerd/kubelet
- **Build-time integration:** Cache is created during image build (Packer or manual imager), not at runtime

### Two-Component Solution

1. **Cache creation:** `talosctl images cache-create` pulls images and packages them into an OCI directory
2. **Disk embedding:** Talos imager (`ghcr.io/siderolabs/imager`) bakes the OCI cache into the disk image as the IMAGECACHE partition

### Machine Config Requirement

```yaml
machine:
  features:
    imageCache:
      localEnabled: true
```

**Critical:** Must be enabled BEFORE `talosctl bootstrap`. Without this, Talos automatically removes the IMAGECACHE partition on first boot.

## Practical Application

### Create Image Cache

```bash
# 1. List default Talos images
talosctl images default > images.txt

# 2. Add extra images (both tag AND digest references required)
cat extra-images.txt >> images.txt

# 3. Create OCI cache
cat images.txt | talosctl images cache-create --image-cache-path ./image-cache.oci --images=-
```

### Extra Images Format

Both tag and digest references required per image:

```
ghcr.io/fluxcd/helm-controller:v1.1.0
ghcr.io/fluxcd/helm-controller@sha256:4c75ca6c24ceb...
quay.io/cilium/cilium@sha256:d55ec38938854...
```

### Build Disk Image with Cache

```bash
mkdir -p _out/
docker run --rm -t \
  -v $PWD/_out:/secureboot:ro \
  -v $PWD/_out:/out \
  -v $PWD/image-cache.oci:/image-cache.oci:ro \
  -v /dev:/dev --privileged \
  ghcr.io/siderolabs/imager:v<VERSION> metal \
  --image-cache /image-cache.oci
```

For large caches: add `--image-disk-size=3GB`

### Verification Commands

```bash
# Check IMAGECACHE partition
talosctl get discoveredvolumes --nodes <IP> | grep IMAGECACHE

# Check registryd service
talosctl get services --nodes <IP> | grep registryd

# Verify local pulls (remote_addr should be 127.0.0.1)
talosctl logs registryd --nodes <IP> | head -20
```

## Decision Points

| Factor | Use Image Cache | Skip Image Cache |
|--------|----------------|------------------|
| Internet access | Air-gapped or restricted | Full internet |
| Scale | 100+ clusters pulling simultaneously | Small number of clusters |
| Bandwidth | Limited or metered | Abundant |
| Registry infrastructure | Single registry, limited capacity | Distributed/CDN-backed |
| Image consistency | Must guarantee exact versions | Can tolerate pull-time resolution |

### Trade-offs

- **Pro:** Eliminates registry dependency at boot, reduces bootstrap time, prevents registry overload
- **Pro:** Per-node cache -- no shared infrastructure needed
- **Con:** Larger disk images (cache adds 1-3 GB depending on image count)
- **Con:** Cache updates require rebuilding the template image
- **Con:** Must include both tag and digest references for each extra image

## References

- [3000+ Clusters Part 4 - JYSK Tech](https://jysk.tech/3000-clusters-part-4-how-not-to-ddos-your-internal-registry-b230fc596159)
- [Talos Image Cache Documentation](https://www.talos.dev/latest/talos-guides/configuration/image-cache/)
- [Talos Image Factory](https://factory.talos.dev/)
