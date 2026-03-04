# replicated-review

Replicated release and Helm chart architecture review toolkit for Claude Code. Performs structured reviews of vendor Helm charts and Replicated releases, generates customer-facing deliverables, and maintains a living runbook of best practices and antipatterns.

## Installation

```
/plugin marketplace add adamancini/devops-toolkit
/plugin install replicated-review@devops-toolkit
```

Or add to your Clewfile:

```yaml
- name: replicated-review@devops-toolkit
```

## Usage

### Review a Replicated Release

```
/release-review ./path/to/release/
```

This runs a full architecture review covering:

| Component | What gets checked |
|-----------|-------------------|
| Helm Charts | Antipatterns, values structure, security, HA, labels, image management |
| HelmChart CRs | Template function correctness, optionalValues, builder key, air-gap, YAML quoting |
| Config CR | Field types, boolean patterns, conditionals, required fields |
| Application CR | Status informers, ports, links |
| Preflight/SupportBundle | Coverage assessment against deployed components |
| Embedded Cluster Config | Extensions, overrides, node roles, built-in component interactions |

The command generates a customer-facing deliverable at `./release-review-<vendor>-<date>.md` and auto-updates the runbook if new patterns are discovered.

### Regenerate the Runbook

```
/sync-runbook
```

Consolidates all knowledge from the agent, reference documents, and incremental runbook additions into a clean, deduplicated, publication-ready document. Use this periodically to clean up accumulated additions and before exporting to Google Docs.

### Contribute Runbook Updates

```
/contribute-runbook
```

After running reviews that update the runbook, use this command to contribute your changes back to the shared repository. It opens a GitHub PR via fork (requires `gh` CLI) or exports a patch file if `gh` is unavailable.

## Exporting to Google Docs

The runbook (`skills/release-review/runbook.md`) is written in clean markdown with no plugin-specific syntax. To update the shared Google Doc:

1. Run `/sync-runbook` to produce a clean version
2. Copy the contents of `runbook.md`
3. Paste into the Google Doc

## Contributing

The runbook is automatically updated after reviews. To contribute your updates back to the shared repository:

1. Run `/contribute-runbook` -- this opens a PR via GitHub fork
2. If `gh` CLI is not installed, it exports a patch file with manual submission instructions
3. Other team members get updates on next plugin refresh after the PR is merged

## Plugin Structure

```
plugins/replicated-review/
├── agents/
│   └── helm-chart-developer.md         # Review agent with Helm + KOTS knowledge
├── skills/
│   └── release-review/
│       ├── SKILL.md                    # Review procedure definition
│       ├── runbook.md                  # Living runbook (continuously updated)
│       ├── deliverable-template.md     # Customer-facing output template
│       └── reference/
│           ├── antipatterns.md         # Helm antipattern catalog
│           ├── kots-templating.md      # KOTS/Replicated template reference
│           └── embedded-cluster.md     # Embedded Cluster review items
└── commands/
    ├── contribute-runbook.md            # /contribute-runbook command
    ├── release-review.md               # /release-review command
    └── sync-runbook.md                 # /sync-runbook command
```
