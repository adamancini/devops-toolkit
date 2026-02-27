# replicated-review

Replicated release and Helm chart architecture review toolkit for Claude Code. Performs structured reviews of vendor Helm charts and Replicated releases, generates customer-facing deliverables, and maintains a living runbook of best practices and antipatterns.

## Installation

```
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

## Exporting to Google Docs

The runbook (`skills/release-review/runbook.md`) is written in clean markdown with no plugin-specific syntax. To update the shared Google Doc:

1. Run `/sync-runbook` to produce a clean version
2. Copy the contents of `runbook.md`
3. Paste into the Google Doc

## Contributing

This plugin lives in the devops-toolkit marketplace. To contribute:

1. Make changes to files under `plugins/replicated-review/`
2. Commit and push to the marketplace repo
3. Other team members get updates on next plugin refresh

The runbook is automatically updated after reviews. New antipatterns and gotchas discovered during reviews are appended with date annotations. Run `/sync-runbook` periodically to clean up accumulated additions.

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
    ├── release-review.md               # /release-review command
    └── sync-runbook.md                 # /sync-runbook command
```
