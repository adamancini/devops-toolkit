# Proxmox Manager Phase 5: Cluster Lifecycle Management

- **Date:** 2026-02-07
- **Status:** Implemented
- **Version:** 0.4.0 -> 0.5.0

## Summary

Phase 5 adds cluster lifecycle management to the proxmox-manager skill. Clusters are defined as YAML profiles for repeatable create/destroy cycles, with Talos Kubernetes bootstrap and Flux CD integration. The Ansible Integration section is expanded with playbook documentation, Talos-specific delegation commands, and fleet-wide operation patterns.

## New Capabilities

- **Cluster profile schema** -- declarative YAML format defining nodes, sizing, network, template, tags, and Flux configuration
- **Cluster create runbook** -- 15-step procedure for full cluster provisioning (VM cloning, configuration, Talos bootstrap, Flux bootstrap)
- **Cluster teardown runbook** -- 8-step procedure for safe cluster destruction with dry-run support
- **Cluster rebuild** -- compound operation (teardown + create) documented in SKILL.md
- **Cluster status queries** -- tag-based AND-logic filtering for cluster membership
- **Expanded Ansible integration** -- playbook catalog, Talos provisioning delegation, fleet-wide operations with --limit patterns

## New Runbooks

| Runbook | Steps | Requires |
|---------|-------|----------|
| `cluster-create.md` | 15 | api, ssh, talosctl, flux |
| `cluster-teardown.md` | 8 | api |

## New Cluster Profiles

| Profile | Type | Control Plane | Workers | Template |
|---------|------|---------------|---------|----------|
| `talos-staging.yaml` | talos | 3 (spread) | 0 | 101 |

## RBAC

No changes needed. The existing custom role has sufficient privileges for all cluster lifecycle operations (VM.Allocate, VM.Clone, VM.Config.*, VM.PowerMgmt, Datastore.AllocateSpace).

## Files Modified

- `skills/proxmox-manager/SKILL.md` -- expanded Cluster Profiles section (schema + conventions), added Cluster Lifecycle Operations to Core Operations Reference, expanded Ansible Integration section, bumped to v0.5.0
- `skills/proxmox-manager/clusters/talos-staging.yaml` -- new cluster profile
- `skills/proxmox-manager/runbooks/cluster-create.md` -- new runbook
- `skills/proxmox-manager/runbooks/cluster-teardown.md` -- new runbook
- `docs/plans/2026-02-07-proxmox-manager-phase5.md` -- this plan document
