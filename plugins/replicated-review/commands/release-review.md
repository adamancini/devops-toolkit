# Release Review

Perform a Replicated release architecture review using the `helm-chart-developer` agent with the `release-review` skill.

## Arguments

When invoked WITH a path argument:
```
I'll perform a Replicated release architecture review of [path].
```

When invoked WITHOUT arguments:
```
I need a path to the release directory to review.

Please provide the path to the directory containing your Replicated release assets (Helm charts, KOTS custom resources, etc.).
```

Wait for the user to provide the path before proceeding.

## Execution

Delegate the entire review to the `helm-chart-developer` agent. The agent has the `release-review` skill bound, which contains the runbook, deliverable template, and reference documents.

Instruct the agent to execute these four phases in order:

### Phase 1 - Discovery

Scan the target directory recursively for release components:

- `Chart.yaml` files (Helm charts and subcharts)
- YAML files containing `kind: HelmChart` (KOTS HelmChart custom resources)
- YAML files containing `kind: Config` (KOTS Config)
- YAML files containing `kind: Application` (KOTS Application)
- YAML files containing `kind: Preflight` or `kind: SupportBundle`
- YAML files containing `kind: EmbeddedClusterConfig`

Report what was found and call out any expected components that are missing.

### Phase 2 - Analysis

Review each discovered component against the runbook checklist:

- **Helm charts:** antipattern scan (arrays as keys, excessive nesting, Bitnami deps, hardcoded namespaces, template naming collisions), values structure, security contexts, HA configuration, common labels
- **HelmChart CRs:** template function correctness (`repl{{}}` vs `{{repl}}`), optionalValues with `recursiveMerge: true`, builder key with static values, air-gap image rewriting, YAML quoting
- **Config CR:** field types, boolean patterns (`"0"`/`"1"` not `true`/`false`), conditional `when` clauses, hidden generated secrets using `value:` not `default:`
- **Cross-referencing:** HelmChart CR values vs chart `values.yaml` coverage, Config fields mapped through HelmChart CR, builder key covering all images
- **Preflight/SupportBundle:** coverage of critical checks (disk, memory, k8s version, connectivity, storage class)
- **EmbeddedClusterConfig:** extensions, unsupported overrides, node roles, distribution-specific conditionals

### Phase 3 - Deliverable

Generate a customer-facing review document:

1. Read the deliverable template from the release-review skill
2. Populate it with severity-rated findings: Critical, High, Medium, Low
3. Write the output to `./release-review-<vendor>-<date>.md` where `<vendor>` comes from the primary Chart.yaml name and `<date>` is today's date (YYYY-MM-DD format)
4. Tell the user the absolute path where the deliverable was written

### Phase 4 - Runbook Update

Check whether the review surfaced new knowledge:

1. Compare findings against the current runbook
2. If new antipatterns, gotchas, or checklist items were discovered, append them to the appropriate runbook section with `<!-- added: YYYY-MM-DD -->` annotations
3. If the runbook was updated, commit changes to the plugin repo with a descriptive message
4. Report whether the runbook was updated and what was added

## Summary

After all phases complete, provide a summary:

- What was reviewed (chart name, version, components found)
- Issue counts by severity (Critical / High / Medium / Low)
- Where the deliverable was written (absolute path)
- Whether the runbook was updated
