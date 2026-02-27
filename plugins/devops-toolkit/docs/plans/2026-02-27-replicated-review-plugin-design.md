# Design: replicated-review Plugin

**Date:** 2026-02-27
**Status:** Approved

## Problem

Replicated CREs perform Helm Chart Architecture Reviews for vendor applications. The review process is documented in a runbook (currently a Google Doc/Desktop markdown file) and produces a customer-facing deliverable. Knowledge about antipatterns, KOTS templating gotchas, and best practices is scattered across the runbook, the helm-chart-developer agent, Google Docs, and tribal knowledge. There is no automated way to:

1. Run a structured review against a Replicated release
2. Generate a formatted deliverable from the review
3. Capture new discoveries back into the runbook
4. Distribute updated knowledge to the team

## Solution

A new standalone plugin called `replicated-review` within the devops-toolkit marketplace. It contains a forked helm-chart-developer agent with Replicated-specific review capabilities, a skill with the runbook and deliverable template, and slash commands that orchestrate the review workflow.

## Architecture

### Knowledge Model: Hybrid

The agent contains deep, machine-optimized knowledge (Helm best practices, KOTS templating gotchas, production lessons). The runbook is a curated, human-readable overlay suitable for redistribution to non-plugin-users via Google Docs.

- **Agent .md**: Complete technical knowledge, esoteric details, code patterns
- **runbook.md**: Human-readable review procedure and checklist
- **deliverable-template.md**: Customer-facing output format
- **reference/**: Detailed catalogs (antipatterns, KOTS templating, EC specifics)

### Plugin Structure

```
plugins/replicated-review/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   └── helm-chart-developer.md         # Forked from devops-toolkit, self-contained
├── skills/
│   └── release-review/
│       ├── SKILL.md                    # Review procedure skill definition
│       ├── runbook.md                  # Human-readable runbook (continuously updated)
│       ├── deliverable-template.md     # Customer-facing review output template
│       └── reference/
│           ├── antipatterns.md         # Helm antipattern catalog
│           ├── kots-templating.md      # KOTS/Replicated template gotchas
│           └── embedded-cluster.md     # EC-specific review items
├── commands/
│   ├── release-review.md              # /release-review command
│   └── sync-runbook.md               # /sync-runbook command
└── README.md
```

### Registration

New entry in `.claude-plugin/marketplace.json` plugins array:

```json
{
  "name": "replicated-review",
  "source": "./plugins/replicated-review",
  "version": "1.0.0",
  "description": "Replicated release and Helm chart architecture review toolkit",
  "author": { "name": "Ada Mancini" }
}
```

New entry in `Clewfile.yaml`:

```yaml
- name: replicated-review@devops-toolkit
```

## Component Design

### Agent: helm-chart-developer

Forked from the existing devops-toolkit agent (589 lines). Contains:

- General Helm 3 best practices and standards
- Lessons learned from production (secret generation, init containers, ConfigMap permissions, etc.)
- Replicated/KOTS templating interactions (YAML quoting, boolean gotchas, optionalValues, syntax rules, air-gap patterns, etc.)
- New: instructions to load `release-review` skill when performing reviews
- New: post-review behavior to check for new discoveries and append to runbook

Frontmatter:

```yaml
---
name: helm-chart-developer
description: "Use this agent for Helm chart development, Replicated release reviews, and KOTS integration work..."
model: opus
color: pink
skills: release-review
---
```

### Skill: release-review

**SKILL.md** defines the review procedure and triggers. It instructs the agent to:

1. Discover release components
2. Review each component type against the runbook checklist
3. Generate the deliverable
4. Update the runbook with new findings

**runbook.md** structure (imported from current Desktop document, enhanced):

1. Initial Information Gathering
2. Expected Components Checklist
3. Antipatterns to Identify
4. Patterns Requiring Deep Investigation
5. General Kubernetes Architecture
6. Common Labels
7. Testing and Validation
8. Review Deliverable Structure
9. Additional Resources
10. Changelog

**deliverable-template.md** (imported from current Desktop document):
- Summary with status and issue counts
- Replicated Platform Integration table
- Critical Antipatterns section
- Severity-rated Findings (Critical/High/Medium/Low)
- Action Items
- Next Steps

### Command: /release-review

**Invocation:** `/release-review [path]`

**Workflow:**

Phase 1 - Discovery:
- Scan directory for release components (Helm charts, HelmChart CRs, Config, Application, Preflight, SupportBundle, EmbeddedClusterConfig)
- Report what was found and what is missing

Phase 2 - Analysis:
- Helm charts: antipattern scan, values structure, security, HA, labels
- HelmChart CRs: template function correctness, optionalValues/recursiveMerge, builder key, air-gap rewriting, YAML quoting
- Config CR: field types, boolean patterns, conditionals, required fields
- Cross-referencing: HelmChart values vs chart values.yaml, Config coverage, builder image coverage
- Preflight/SupportBundle: coverage assessment
- EC config: extensions, overrides, compatibility

Phase 3 - Deliverable:
- Populate deliverable template with severity-rated findings
- Write to `./release-review-<vendor>-<date>.md`

Phase 4 - Knowledge Update:
- Compare findings against current runbook
- If new antipatterns or gotchas discovered, append to runbook with date annotation
- Commit runbook update to plugin repo

### Command: /sync-runbook

**Invocation:** `/sync-runbook`

Regenerates the entire runbook from the agent's accumulated knowledge:
- Reads agent .md, runbook.md, and all reference/ files
- Produces a clean, deduplicated, well-organized document
- Removes redundancy from incremental appends
- Strips machine annotations for publication-ready markdown
- Writes back to runbook.md and commits
- Output is suitable for direct copy-paste into Google Docs

## Review Scope: What Gets Reviewed

| Component | Detection | Review Areas |
|-----------|-----------|-------------|
| Helm Charts | `*.tgz`, `charts/`, `Chart.yaml` | Antipatterns, values, security, HA, labels, templating |
| HelmChart CRs | `kind: HelmChart` | Template functions, optionalValues, builder, air-gap, quoting |
| Config CR | `kind: Config` | Field types, booleans, conditionals, required fields |
| Application CR | `kind: Application` | Status informers, ports, links |
| Preflight specs | `kind: Preflight` | Coverage (disk, memory, K8s version, storage, connectivity) |
| Support Bundle | `kind: SupportBundle` | Collectors, analyzers, failure mode coverage |
| EC config | `kind: EmbeddedClusterConfig` | Extensions, overrides, node roles |
| Images | All manifests | Registry/repo/tag split, ImagePullSecrets, proxy usage, air-gap |

## Runbook Lifecycle

1. **Incremental updates**: After each review, new discoveries are appended with date stamps
2. **Clean regeneration**: `/sync-runbook` produces a deduplicated, publication-ready document
3. **Google Docs export**: Manual copy-paste from clean markdown (no plugin-specific syntax in prose)

## Distribution

- Plugin lives in the devops-toolkit marketplace git repo
- Team members install via `replicated-review@devops-toolkit`
- Updates flow through git pushes; Claude auto-updates the plugin
- Contributions via PRs to the marketplace repo
- Google Docs is a point-in-time export for external stakeholders

## What Stays in devops-toolkit

The original helm-chart-developer agent remains in devops-toolkit for general Helm work unrelated to Replicated reviews. No breaking changes to existing workflows.

## Implementation Sequence

1. Create plugin directory structure and manifests
2. Fork helm-chart-developer agent with review instructions
3. Import and clean up runbook.md from Desktop document
4. Import deliverable-template.md from Desktop document
5. Extract reference documents (antipatterns, KOTS templating, EC)
6. Write SKILL.md for release-review
7. Write /release-review command
8. Write /sync-runbook command
9. Register plugin in marketplace.json and Clewfile
10. Test: run a review against an existing platform-examples application
11. Validate: export runbook to verify Google Docs readability
