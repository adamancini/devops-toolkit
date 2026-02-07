# Proxmox Manager Phase 4: Advanced Operations

**Date:** 2026-02-07
**Status:** Implemented
**Version:** 0.3.0 -> 0.4.0

## Summary

Phase 4 extends the proxmox-manager skill with advanced operational capabilities:

1. **Migration** -- Live and offline VM migration between nodes, pre-migration resource checks
2. **Bulk Tag Operations** -- Filter, start, stop, tag, and untag VMs by tag with exact matching
3. **Snapshot Management** -- Create, list, rollback, and delete snapshots via API
4. **Backup Management** -- On-demand vzdump backups, restore from backup, list/delete backups
5. **Storage Management** -- Storage pool listing, ISO management, orphaned disk identification and cleanup

## New Runbooks

- `node-evacuation.md` -- Multi-step procedure to evacuate all VMs from a node before maintenance
- `bulk-snapshot-by-tag.md` -- Create snapshots across all VMs matching a given tag

## RBAC

No RBAC changes required. The existing `ClaudeCodeManager` role already includes all needed privileges:
`VM.Migrate`, `VM.Snapshot`, `VM.Snapshot.Rollback`, `VM.Backup`, `Datastore.Allocate`,
`Datastore.AllocateSpace`, `Datastore.Audit`, `Sys.Audit`.

## Files Modified

- `skills/proxmox-manager/SKILL.md` -- 5 new Core Operations Reference sections, version bump
- `skills/proxmox-manager/runbooks/node-evacuation.md` -- new runbook
- `skills/proxmox-manager/runbooks/bulk-snapshot-by-tag.md` -- new runbook
- `docs/plans/2026-02-07-proxmox-manager-phase4.md` -- this plan document
