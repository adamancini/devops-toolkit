---
name: talos-version-upgrade
description: Template-based Talos version upgrade -- new factory image, new PVE template, redeploy cluster
image_type: none
requires: [talosctl, kubectl, api, ssh]
---

# Talos Version Upgrade (Template-Based)

Use this runbook for **major version upgrades**, factory image changes, or extension set changes. For minor/patch upgrades within the same extension set, use `talos-upgrade.md` (in-place `talosctl upgrade`).

**Why template-based:** Talos is immutable. When the factory image or extension set changes, a new OS image must be built and deployed. The cleanest path is: build new image, create new PVE template, tear down old VMs, clone from the new template, apply machine configs, bootstrap.

## Parameters

- profile: Cluster profile name (required)
- target_talos_version: New Talos version (e.g., "1.12.4")
- target_k8s_version: New Kubernetes version (e.g., "1.35.0")
- new_schematic_id: Factory schematic ID for the new image (generate via `talos-image-factory.md` if extensions changed; reuse existing if only version changed)
- new_template_vmid: VMID for the new template (allocate from `vmid_ranges.templates`)

## Prerequisites

- Current cluster is healthy and backed up (etcd snapshot taken)
- `talosctl` CLI version matches or exceeds `target_talos_version`
- Cluster profile exists with current configuration
- Network connectivity to Proxmox API and cluster nodes

## Steps

### Phase 1: Build New Factory Image

1. **Determine schematic ID** (local)

   If extensions are unchanged, reuse the existing `talos.factory.schematic_id` from the cluster profile. The same schematic with a different Talos version produces a new image.

   If extensions need to change, generate a new schematic first. See `runbooks/talos-image-factory.md`.

2. **Construct image URLs** (local)

   ```
   TEMPLATE_IMAGE=https://factory.talos.dev/image/<SCHEMATIC_ID>/v<target_talos_version>/nocloud-amd64.raw.xz
   INSTALLER=factory.talos.dev/installer/<SCHEMATIC_ID>:v<target_talos_version>
   ```

### Phase 2: Create New PVE Template

3. **Create template from the new image** (API + SSH)

   Follow `runbooks/talos-template-create.md` with:
   - `image_url`: the `TEMPLATE_IMAGE` URL from step 2
   - `vmid`: `new_template_vmid`
   - `name`: `talos-<target_talos_version>` (e.g., `talos-1.12.4`)
   - Tag with `template;talos`

   After template creation, verify it appears in the template list:

   ```bash
   curl -sk \
     -H "Authorization: PVEAPIToken=$(pass show <PASS_PATH> | head -1)=$(pass show <PASS_PATH> | tail -1)" \
     "https://<NODE_HOST>:8006/api2/json/cluster/resources?type=vm" \
     | jq '.data[] | select(.vmid == <new_template_vmid>)'
   ```

### Phase 3: Take Backups

4. **Take etcd snapshot** (local)

   ```bash
   talosctl etcd snapshot <config_dir>/etcd-pre-version-upgrade-$(date +%Y%m%d).snapshot \
     --nodes <CP_IP1>
   ```

5. **Record current cluster state** (local)

   ```bash
   talosctl version --nodes <CP_IP1>
   kubectl get nodes -o wide
   talosctl get members
   ```

   Save this output for rollback reference.

### Phase 4: Tear Down Old Cluster

6. **Tear down existing VMs** (API)

   Follow `runbooks/cluster-teardown.md` with the current cluster profile. This shuts down and deletes all VMs matching the profile's tags.

   **IMPORTANT:** Ensure etcd snapshot from step 4 is stored off-cluster before proceeding.

### Phase 5: Update Profile and Redeploy

7. **Update cluster profile** (local)

   Update the profile YAML with new values:

   ```yaml
   talos:
     version: "<target_talos_version>"
     kubernetes_version: "<target_k8s_version>"
     factory:
       schematic_id: "<new_schematic_id>"
   template: <new_template_vmid>
   ```

8. **Create new VMs from updated template** (API)

   Follow `runbooks/cluster-create.md` with the updated profile. This clones VMs from the new template, configures them, and starts them.

9. **Bootstrap Talos cluster** (local)

   Follow `runbooks/talos-cluster-bootstrap.md` with the updated profile. This generates configs with the new installer image, applies them, bootstraps etcd, and verifies health.

   Key: The `talosctl gen config` step will use the new `INSTALLER` reference from step 2, ensuring nodes pull the correct Talos version on first boot.

### Phase 6: Verify and Finalize

10. **Verify new cluster** (local)

    ```bash
    talosctl version --nodes <CP_IP1>
    talosctl health
    kubectl get nodes -o wide
    talosctl get extensions --nodes <CP_IP1>
    ```

    Expected:
    - Talos version matches `target_talos_version`
    - Kubernetes version matches `target_k8s_version`
    - All nodes healthy and Ready
    - Extensions match the schematic

11. **Bootstrap Flux CD** (local -- if applicable)

    ```bash
    flux bootstrap git \
      --url=<FLUX_REPO> \
      --path=<FLUX_PATH> \
      --branch=<FLUX_BRANCH>
    ```

12. **Commit profile changes** (local)

    ```bash
    git add clusters/<profile_name>.yaml
    git commit -m "feat(talos): upgrade to Talos v<target_talos_version> with K8s <target_k8s_version>"
    ```

## Cleanup

- Remove old PVE template if no longer needed (keep for rollback if desired)
- Remove pre-upgrade etcd snapshot after confirming stability (or retain per backup policy)
- Update `talosctl` client to match the new cluster version

## Rollback

If the new cluster fails to bootstrap:
1. Tear down the new VMs (`cluster-teardown.md`)
2. Revert the profile to the previous version
3. Redeploy from the old template (which was preserved during teardown)
4. Restore etcd from the pre-upgrade snapshot if needed

## Notes

- **Template preservation:** Cluster teardown does not delete templates (filtered by `select(.template != 1)`). The old template remains available for rollback.
- **Secrets reuse:** If you reuse the existing `secrets.yaml`, the new cluster will have the same CA and bootstrap tokens. This is required if you want to restore etcd from the pre-upgrade snapshot.
- **Flux state:** Flux reconciles from Git, so application state is preserved across cluster rebuilds. Persistent data depends on your storage backend (CSI volumes, backups).
- **When to use this vs in-place:** Use this runbook when the factory image changes (new extensions, major version jump). Use `talos-upgrade.md` for minor/patch upgrades where only the Talos OS binary changes.
