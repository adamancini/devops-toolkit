# Cluster Context Manager Skill Design

## Problem

Managing kubectl and talosctl contexts across multiple clusters (production, staging, ephemeral CMX) requires coordinated operations that span two tools. Stale contexts accumulate from destroyed clusters, naming is inconsistent, and there is no single skill that guides Claude through these workflows.

## Decision

Create a self-contained skill (Pattern A) at `plugins/devops-toolkit/skills/cluster-context-manager/SKILL.md` that provides unified cluster context management using kubecm for kubectl contexts and native talosctl commands for talosctl contexts.

## Scope

### In Scope

- kubecm command reference (add, merge, switch, delete, clear, rename, export, namespace, alias, list)
- talosctl context commands (context, contexts, merge)
- Unified status check workflow (both tools)
- Post-bootstrap context naming (after `talosctl kubeconfig`)
- Stale context cleanup (CMX leftovers, destroyed clusters)
- Merging external kubeconfig files
- Exporting contexts for sharing
- Shell integration (`~/.zshrcd/conf.d/kubecm.zsh` with completions and env vars)
- Cross-references to proxmox-manager and replicated-cli skills

### Out of Scope

- No standalone agent (skill is sufficient for 1-2 command operations)
- No talosctl cluster operations (bootstrap, upgrade stay in proxmox-manager)
- No cloud provider imports (not currently used)
- No kubecm registry feature (single user, not team distribution)

## Autonomy Model

- **Auto-execute:** `kubecm list`, `kubecm switch`, `kubecm export`, `talosctl config contexts`, status checks
- **Confirm first:** `kubecm delete`, `kubecm clear`, `kubecm merge`, `kubecm rename`, `kubecm add`

## Naming Convention

kubectl contexts follow the `admin@cluster-name` pattern (e.g., `admin@talos-staging`, `admin@talos-production`). This aligns with the existing convention and maps naturally to talosctl context names (`staging`, `annarchy`).

## Skill Structure

Single `SKILL.md` with these sections:

1. Overview
2. Autonomy model
3. Shell integration setup
4. Naming conventions
5. Command reference (kubecm table + talosctl table)
6. Workflows (status, post-bootstrap, cleanup, merge, export)
7. Integration points (proxmox-manager, replicated-cli, home-manager)
8. Troubleshooting

## Integration Points

### proxmox-manager

- Cluster bootstrap runbook: add kubecm rename step after `talosctl kubeconfig --force`
- Cluster teardown runbook: replace manual `kubectl config delete-*` with `kubecm delete`/`kubecm clear`

### home-manager

- Route kubeconfig management questions to this skill

### zsh-config-manager

- Shell integration file follows conf.d conventions (command guard, yadm tracking)

### Scope Boundary

This skill manages contexts only. Cluster lifecycle (bootstrap, upgrade, teardown) stays in proxmox-manager. The integration is that proxmox-manager calls out to this skill's conventions for the context-management portions of those workflows.

## Follow-up Work

After creating the skill:

1. Update proxmox-manager runbooks with kubecm cross-references
2. Update home-manager agent routing table
3. Create `~/.zshrcd/conf.d/kubecm.zsh` and track with yadm
