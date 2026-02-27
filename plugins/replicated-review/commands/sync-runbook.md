# Sync Runbook

I'll regenerate the review runbook by consolidating all knowledge sources into a clean, publication-ready document.

## Execution

### Step 1 - Read All Knowledge Sources

Read the following files to gather the full body of knowledge:

- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/runbook.md` (current runbook, may contain incremental additions)
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/antipatterns.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/kots-templating.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/embedded-cluster.md`
- `${CLAUDE_PLUGIN_ROOT}/agents/helm-chart-developer.md` (agent built-in knowledge)

If a reference file does not exist yet, skip it and note it was missing.

### Step 2 - Regenerate the Runbook

Rewrite `runbook.md` from scratch using the collected knowledge:

1. **Preserve section structure:** 1. Initial Information Gathering through 10. Additional Resources, plus Appendix and Changelog
2. **Deduplicate:** If the same antipattern, gotcha, or checklist item appears in both the runbook and a reference doc, keep one canonical entry in the runbook
3. **Remove incremental cruft:** Strip repeated items that were appended via `<!-- added: ... -->` annotations across multiple reviews
4. **Strip machine annotations:** Remove all `<!-- added: ... -->`, `<!-- last-updated: ... -->`, and similar HTML comments
5. **Clean prose:** Ensure no plugin-internal syntax (`${CLAUDE_PLUGIN_ROOT}`, skill file paths) leaks into the document
6. **Publication-ready markdown:** Output clean markdown suitable for direct copy-paste into Google Docs
7. **Changelog entry:** Add `YYYY-MM-DD: Runbook regenerated via /sync-runbook` using today's date

### Step 3 - Write and Commit

1. Write the regenerated runbook to `${CLAUDE_PLUGIN_ROOT}/skills/release-review/runbook.md`
2. Commit to the plugin repo with message: `docs(replicated-review): regenerate runbook via /sync-runbook`
3. Push to the remote if it is available; if the push fails, note it and continue

### Step 4 - Report

Provide a summary covering:

- Sections updated, items added, items removed, items deduplicated
- Confirm the runbook is ready for export to Google Docs
- Remind: "Copy the contents of runbook.md to update the shared Google Doc"
