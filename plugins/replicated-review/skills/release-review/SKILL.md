---
name: release-review
description: Use when performing a Replicated release architecture review, Helm chart review for Replicated distribution, generating a review deliverable, or updating the review runbook. Trigger phrases include "review this release", "review this chart", "helm review", "release review", "architecture review", "generate deliverable", "update runbook", "sync runbook".
version: 1.0.0
---

# Release Review Skill

Orchestrates structured architecture reviews of Replicated releases and Helm charts. Produces a customer-facing deliverable and keeps the review runbook current.

## Reference Files

Read these files as needed during the review:

- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/runbook.md` -- Review procedure and checklist
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/deliverable-template.md` -- Customer-facing output template
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/antipatterns.md` -- Helm antipattern catalog
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/kots-templating.md` -- KOTS templating reference
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/embedded-cluster.md` -- EC-specific review items

## Review Procedure

### Phase 1: Discovery

Scan the target directory and report what is present and what is missing.

1. **Helm charts**: Look for `Chart.yaml`, `values.yaml`, `templates/` directories, and `.tgz` archives. Record chart name, version, and dependencies.
2. **KOTS kinds**: Scan all YAML files for these `kind` values:
   - `HelmChart` (the KOTS CR, not the Helm chart itself)
   - `Config`
   - `Application`
   - `Preflight`
   - `SupportBundle`
3. **Embedded Cluster config**: Scan for `kind: EmbeddedClusterConfig`.
4. **Report**: List every component found with its file path. Flag any expected components that are absent (e.g., no Preflight, no SupportBundle, no Replicated SDK dependency).

### Phase 2: Analysis

Read `runbook.md` for the full checklist. For each component type found, perform the checks below.

**Helm Charts**
- Read `reference/antipatterns.md`. Check each antipattern against the chart.
- Verify values.yaml structure: progressive disclosure, camelCase keys, maps over arrays, sufficient comments.
- Check security contexts (runAsNonRoot, drop ALL, readOnlyRootFilesystem).
- Check standard labels (app.kubernetes.io/name, instance, version, managed-by).
- Check resource requests/limits on all containers, init containers, and jobs.
- Check image management: separate registry/repository/tag fields, imagePullSecrets support.
- Check for hardcoded namespaces, literal Namespace resources, or multiple YAML documents per file.

**HelmChart CRs**
- Read `reference/kots-templating.md`.
- Verify `apiVersion: kots.io/v1beta2`.
- Check template function syntax: `repl{{ }}` for value expressions, `{{repl }}` for control flow.
- Check YAML quoting: single quotes when `repl{{ }}` contains inner double quotes.
- Verify every `optionalValues` entry has `recursiveMerge: true`.
- Verify `builder` key contains only static/hardcoded image references (no template functions).
- Check air-gap patterns: `HasLocalRegistry`, `LocalRegistryHost`, `LocalRegistryNamespace`, `ImagePullSecretName`.
- Check type conversions: `ParseInt` for ports/replicas, `ParseBool` for booleans, `ConfigOptionData` for file types.

**Config CR**
- Boolean fields use `type: bool` and are compared with `ConfigOptionEquals "field" "1"`.
- Required fields have sensible defaults.
- Conditional `when` clauses use correct syntax and reference valid item names.
- Generated secrets use `value:` with `hidden: true` (not `default:`).

**Application CR**
- `statusInformers` cover all deployed components (Deployments, StatefulSets, Services).
- Conditional informers use `{{repl if}}...{{repl end}}` syntax correctly.
- `ports` and `links` are configured for Admin Console access.

**Preflight and SupportBundle**
- Assess coverage: do checks and collectors correspond to what the chart actually deploys?
- Look for disk, memory, CPU, Kubernetes version, storage class, and connectivity checks.
- Look for application log collectors, database checks, and configuration snapshots.

**Embedded Cluster Config**
- Read `reference/embedded-cluster.md`.
- Verify extensions are appropriate and complete.
- Check for unsupported overrides and document justification if present.
- Verify node role configuration.
- Confirm ingress options are hidden on EC (built-in ingress controller).
- Check for distribution-specific conditionals (`ne Distribution "embedded-cluster"`).

**Cross-Referencing**
- Verify HelmChart CR `spec.values` map correctly to the chart's `values.yaml` schema.
- Verify Config CR covers all user-configurable options exposed in the chart.
- Verify the `builder` key lists every conditional image so air-gap bundles are complete.
- Check the four-way contract: `values.yaml` <-> Config <-> HelmChart CR <-> development values.

### Phase 3: Deliverable Generation

1. Read `deliverable-template.md`.
2. Populate every section with findings from Phases 1 and 2.
3. Categorize each finding by severity: **Critical**, **High**, **Medium**, **Low**.
4. Fill in the Replicated Platform Integration table, HelmChart CR Assessment table, and Config CR Assessment table.
5. Populate the Action Items section ordered by priority.
6. Set the vendor name from `Chart.yaml` metadata or user input.
7. Write the completed deliverable to `./release-review-<vendor>-<YYYY-MM-DD>.md` in the current working directory.

### Phase 4: Runbook Update

1. Compare every finding from Phase 2 against `runbook.md`.
2. If a new antipattern, gotcha, or checklist item was discovered that is NOT already documented:
   - Append it to the appropriate section in `runbook.md`.
   - Include a concrete code example (correct and incorrect) for any new antipattern.
   - Annotate new items with `<!-- added: YYYY-MM-DD -->`.
   - Keep prose concise and free of plugin syntax (the runbook must paste cleanly into Google Docs).
3. Do not reorganize existing sections or duplicate items already present.
4. If changes were made, commit to the plugin repo:
   ```
   cd ${CLAUDE_PLUGIN_ROOT} && git add skills/release-review/runbook.md && git commit -m "docs(runbook): add findings from <vendor> review"
   ```

## Sync Runbook Procedure

When the user invokes `/sync-runbook`:

1. Read `runbook.md` and all files under `reference/`.
2. Regenerate a clean, deduplicated runbook that:
   - Maintains the standard section structure (sections 1 through 10).
   - Incorporates knowledge from all reference docs.
   - Removes redundant items accumulated from incremental appends.
   - Strips machine annotations (`<!-- added: ... -->`).
   - Produces clean, publication-ready markdown suitable for Google Docs.
3. Write the result back to `runbook.md`.
4. Update the Changelog section with the sync date and summary of changes.
5. Commit to the plugin repo.
6. Report what changed: sections updated, items added, items removed.
