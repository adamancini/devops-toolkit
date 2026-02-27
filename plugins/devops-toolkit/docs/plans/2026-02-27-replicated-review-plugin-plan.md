# replicated-review Plugin Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a standalone `replicated-review` plugin in the devops-toolkit marketplace that automates Replicated release and Helm chart architecture reviews, generates customer-facing deliverables, and maintains a living runbook.

**Architecture:** New plugin under `plugins/replicated-review/` with a forked helm-chart-developer agent, a `release-review` skill containing runbook and deliverable template, and two slash commands (`/release-review`, `/sync-runbook`). Components are auto-discovered by Claude Code via directory convention.

**Tech Stack:** Claude Code plugin system (markdown agents/skills/commands with YAML frontmatter), Git for distribution via devops-toolkit marketplace.

---

### Task 1: Create Plugin Directory Structure and Manifest

**Files:**
- Create: `plugins/replicated-review/.claude-plugin/plugin.json`

**Step 1: Create the directory tree**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
mkdir -p plugins/replicated-review/.claude-plugin
mkdir -p plugins/replicated-review/agents
mkdir -p plugins/replicated-review/skills/release-review/reference
mkdir -p plugins/replicated-review/commands
```

**Step 2: Write plugin.json**

Create `plugins/replicated-review/.claude-plugin/plugin.json`:

```json
{
  "name": "replicated-review",
  "version": "1.0.0",
  "description": "Replicated release and Helm chart architecture review toolkit. Performs structured reviews of vendor Helm charts and Replicated releases, generates customer-facing deliverables, and maintains a living runbook of best practices and antipatterns.",
  "author": {
    "name": "Ada Mancini"
  },
  "homepage": "https://github.com/adamancini/devops-toolkit",
  "repository": "https://github.com/adamancini/devops-toolkit",
  "license": "MIT",
  "keywords": ["replicated", "helm", "kots", "review", "architecture", "kubernetes", "embedded-cluster"]
}
```

**Step 3: Register in marketplace.json**

Edit `~/.claude/plugins/marketplaces/devops-toolkit/.claude-plugin/marketplace.json` to add a new entry to the `plugins` array:

```json
{
  "name": "replicated-review",
  "source": "./plugins/replicated-review",
  "version": "1.0.0",
  "description": "Replicated release and Helm chart architecture review toolkit",
  "author": {
    "name": "Ada Mancini"
  }
}
```

**Step 4: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(replicated-review): scaffold plugin structure and manifests"
```

---

### Task 2: Fork the helm-chart-developer Agent

**Files:**
- Read: `plugins/devops-toolkit/agents/helm-chart-developer.md` (source, 589 lines)
- Create: `plugins/replicated-review/agents/helm-chart-developer.md`

**Step 1: Copy the existing agent**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
cp plugins/devops-toolkit/agents/helm-chart-developer.md plugins/replicated-review/agents/helm-chart-developer.md
```

**Step 2: Update the frontmatter**

Replace the existing frontmatter (lines 1-6) with:

```yaml
---
name: helm-chart-developer
description: Use this agent when you need to create, review, or improve Helm charts for Kubernetes deployments, perform Replicated release architecture reviews, or debug KOTS/Helm templating interactions. This includes writing new charts from scratch, refactoring existing charts, reviewing vendor releases for Replicated platform integration, and generating architecture review deliverables.\n\nExamples:\n- <example>\n  Context: User wants to review a vendor's Replicated release\n  user: "/release-review ./vendor-release/"\n  assistant: "I'll use the helm-chart-developer agent to perform a structured architecture review of this Replicated release."\n  <commentary>\n  The user is invoking the release-review command, which delegates to this agent.\n  </commentary>\n</example>\n- <example>\n  Context: User needs help creating a new Helm chart\n  user: "I need to create a Helm chart for my Node.js API service"\n  assistant: "I'll use the helm-chart-developer agent to help you create a production-quality Helm chart."\n  <commentary>\n  Standard Helm chart development work.\n  </commentary>\n</example>\n- <example>\n  Context: User wants to debug KOTS templating issues\n  user: "My ConfigOptionEquals is rendering wrong in the HelmChart CR"\n  assistant: "I'll use the helm-chart-developer agent to diagnose the KOTS templating issue."\n  <commentary>\n  KOTS templating debugging is a core capability of this agent.\n  </commentary>\n</example>
model: opus
color: pink
skills: release-review
---
```

Key changes from the original:
- Added `skills: release-review` to bind the skill to the agent
- Updated description to include Replicated release reviews and KOTS debugging
- Added examples covering the review workflow

**Step 3: Add review workflow instructions to the agent body**

After the final line of the existing content (the "Four-Way Contract" section), append:

```markdown

## Review Workflow

When performing a Replicated release or Helm chart architecture review:

1. **Load the release-review skill** for the review procedure, runbook context, and deliverable template
2. **Follow the runbook checklist** systematically — do not skip sections
3. **Generate the deliverable** using the deliverable template, writing it to `./release-review-<vendor>-<date>.md`
4. **Check for new discoveries** — if the review surfaced antipatterns, gotchas, or checklist items not already in the runbook, append them to the appropriate runbook section with a `<!-- added: YYYY-MM-DD -->` annotation
5. **Commit runbook updates** to the plugin repo if changes were made

When updating the runbook after a review:
- Append new items to the existing section structure; do not reorganize
- Include a concrete code example for any new antipattern
- Keep prose concise and free of plugin-specific syntax (the runbook must be copy-pasteable to Google Docs)
- Do not duplicate items already documented
```

**Step 4: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/agents/helm-chart-developer.md
git commit -m "feat(replicated-review): fork helm-chart-developer agent with review workflow"
```

---

### Task 3: Import and Clean Up the Runbook

**Files:**
- Read: `~/Desktop/Helm Chart Architecture Review Runbook (1).md` (source, 931 lines)
- Create: `plugins/replicated-review/skills/release-review/runbook.md`

**Step 1: Import the runbook**

Read the Desktop file. Clean it up:
- Remove Google Docs artifacts (escaped brackets `\[...\]`, stray `\` escapes, `![][image1]` references)
- Normalize markdown formatting (proper fenced code blocks with language hints, consistent heading levels)
- Remove the "Automation Opportunities" section (that's what we're building)
- Ensure all code blocks use proper `yaml` or `bash` language tags
- Strip any remaining Google Docs formatting artifacts

**Step 2: Add KOTS templating section**

After the existing "Antipatterns to Identify" section, add a new subsection incorporating the KOTS templating knowledge we added to the agent earlier. Key items to include in the runbook (human-readable summaries, not the full machine-detail):
- YAML quoting: single quotes when `repl{{ }}` contains inner double quotes
- Boolean config items store "0"/"1", always compare with `ConfigOptionEquals "x" "1"`
- `optionalValues` requires `recursiveMerge: true` for nested values
- `repl{{ }}` vs `{{repl }}` — syntax depends on context
- `Release.IsInstall` / `Release.IsUpgrade` are unreliable under KOTS
- `lookup()` function not supported under KOTS
- Air-gap image rewriting patterns
- The `builder` key must use static values only

**Step 3: Add Embedded Cluster section**

After the KOTS section, add a brief EC-specific review checklist:
- EC config extensions and overrides
- Unsupported overrides validation
- Node role configuration
- Built-in ingress controller considerations (ingress options hidden on EC)

**Step 4: Add Changelog section**

At the end of the document:

```markdown
---

## Changelog

- **2026-02-27**: Initial import from CRE Helm Chart Architecture Runbook. Added KOTS templating gotchas section. Added Embedded Cluster review items.
```

**Step 5: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/skills/release-review/runbook.md
git commit -m "feat(replicated-review): import and enhance runbook from CRE architecture review doc"
```

---

### Task 4: Import the Deliverable Template

**Files:**
- Read: `~/Desktop/Helm Architecture Review Deliverable - Template.md` (source, 135 lines)
- Create: `plugins/replicated-review/skills/release-review/deliverable-template.md`

**Step 1: Import and clean the template**

Read the Desktop file. Clean up the same Google Docs formatting artifacts. The template is already well-structured with placeholder fields `[VENDOR_NAME]`, `[YYYY-MM-DD]`, etc.

Enhancements:
- Add an "Embedded Cluster" row to the Required Components table
- Add a "KOTS Templating" subsection under Critical Antipatterns (for the YAML quoting, boolean, and optionalValues gotchas)
- Ensure all placeholder fields use consistent `[PLACEHOLDER]` syntax

**Step 2: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/skills/release-review/deliverable-template.md
git commit -m "feat(replicated-review): import and enhance deliverable template"
```

---

### Task 5: Create Reference Documents

**Files:**
- Create: `plugins/replicated-review/skills/release-review/reference/antipatterns.md`
- Create: `plugins/replicated-review/skills/release-review/reference/kots-templating.md`
- Create: `plugins/replicated-review/skills/release-review/reference/embedded-cluster.md`

**Step 1: Create antipatterns.md**

Extract the detailed antipattern catalog from the runbook into a standalone reference. This should include all antipatterns with full code examples (correct/incorrect), file paths to check, and detection heuristics. Sections:
- Arrays as Top-Level Keys
- Hardcoded Namespaces
- Bitnami Dependencies
- Platform-Specific External Services
- Template Naming Collisions
- YAML Comments in Template Logic
- Excessive Nesting
- Missing Resource Requests/Limits
- Missing Security Contexts
- Missing Labels

**Step 2: Create kots-templating.md**

Extract the KOTS templating reference from the agent's "Replicated/KOTS Templating Interactions" section (lines 266-589 of the agent). This reference file should be a clean, well-organized version of that content suitable for human readers. It serves as the bridge between the agent's deep knowledge and the runbook's concise checklist.

**Step 3: Create embedded-cluster.md**

Write the EC-specific review reference covering:
- EmbeddedClusterConfig CR structure and validation
- Extension management (what extensions are available, how they affect the installer)
- Unsupported overrides and their risks
- Node role configuration patterns
- Built-in components (ingress controller, storage, registry) and how they affect chart design
- Distribution-specific conditionals (`ne Distribution "embedded-cluster"`)

**Step 4: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/skills/release-review/reference/
git commit -m "feat(replicated-review): add reference documents for antipatterns, KOTS templating, and EC"
```

---

### Task 6: Write the SKILL.md

**Files:**
- Create: `plugins/replicated-review/skills/release-review/SKILL.md`

**Step 1: Write the skill definition**

```yaml
---
name: release-review
description: Use when performing a Replicated release architecture review, Helm chart review for Replicated distribution, generating a review deliverable, or updating the review runbook. Trigger phrases include "review this release", "review this chart", "helm review", "release review", "architecture review", "generate deliverable", "update runbook", "sync runbook".
version: 1.0.0
---
```

The skill body should instruct the agent on:

1. **Discovery phase**: How to scan a directory for release components (Helm charts by Chart.yaml presence, KOTS kinds by `kind:` field, EC configs)
2. **Analysis phase**: What to check for each component type, referencing the runbook sections and reference docs
3. **Deliverable phase**: How to populate the template — read `deliverable-template.md`, fill in findings by severity
4. **Runbook update phase**: How to compare findings against `runbook.md`, append new discoveries with date annotations

Include explicit file paths for the agent to read:
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/runbook.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/deliverable-template.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/antipatterns.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/kots-templating.md`
- `${CLAUDE_PLUGIN_ROOT}/skills/release-review/reference/embedded-cluster.md`

**Step 2: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/skills/release-review/SKILL.md
git commit -m "feat(replicated-review): add release-review skill definition"
```

---

### Task 7: Write the /release-review Command

**Files:**
- Create: `plugins/replicated-review/commands/release-review.md`

**Step 1: Write the command**

Commands don't use YAML frontmatter. The filename becomes the slash command name. The body is the prompt template.

The command should:
1. Accept an optional path argument (default: current directory)
2. Announce what it's doing
3. Instruct the agent to load the `release-review` skill
4. Walk through the four phases: Discovery → Analysis → Deliverable → Runbook Update
5. At the end, report where the deliverable was written and whether the runbook was updated

Key behaviors:
- If no argument provided, ask the user for the path
- If the directory doesn't contain recognizable release components, warn and ask to confirm
- Always generate the deliverable, even if no issues found (document the clean bill of health)

**Step 2: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/commands/release-review.md
git commit -m "feat(replicated-review): add /release-review command"
```

---

### Task 8: Write the /sync-runbook Command

**Files:**
- Create: `plugins/replicated-review/commands/sync-runbook.md`

**Step 1: Write the command**

The command should:
1. Read the current `runbook.md`
2. Read all reference docs from `reference/`
3. Read the agent's knowledge (the full agent .md file)
4. Regenerate a clean, deduplicated runbook that:
   - Maintains the standard section structure (sections 1-10)
   - Incorporates all knowledge from reference docs and agent
   - Removes redundant items that accumulated from incremental appends
   - Strips machine annotations (`<!-- added: ... -->`)
   - Produces clean, Google-Docs-friendly markdown
5. Write the result back to `runbook.md`
6. Commit to the plugin repo
7. Report what changed (sections updated, items added/removed)

**Step 2: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/commands/sync-runbook.md
git commit -m "feat(replicated-review): add /sync-runbook command"
```

---

### Task 9: Write Plugin README

**Files:**
- Create: `plugins/replicated-review/README.md`

**Step 1: Write the README**

Cover:
- What the plugin does (one paragraph)
- Installation (`/plugin install replicated-review@devops-toolkit`)
- Usage: `/release-review ./path/to/release` and `/sync-runbook`
- What gets reviewed (component table)
- How the runbook lifecycle works
- How to contribute (PR to the marketplace repo)
- How to export to Google Docs (copy runbook.md content)

**Step 2: Commit**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git add plugins/replicated-review/README.md
git commit -m "docs(replicated-review): add plugin README"
```

---

### Task 10: Register Plugin and Test

**Files:**
- Modify: `~/.claude/Clewfile.yaml`

**Step 1: Add to Clewfile**

Add this line to the `plugins:` section:

```yaml
  - name: replicated-review@devops-toolkit
```

**Step 2: Push all changes**

```bash
cd ~/.claude/plugins/marketplaces/devops-toolkit
git push origin main
```

**Step 3: Install the plugin**

Restart Claude Code or run the plugin install command to pick up the new plugin.

**Step 4: Smoke test**

Run `/release-review` against an existing platform-examples application:

```bash
/release-review ~/src/github.com/replicatedhq/platform-examples/applications/storagebox/
```

Verify:
- The agent loads the release-review skill
- Discovery phase finds the Helm chart, HelmChart CRs, Config, Application, etc.
- Analysis runs through the runbook checklist
- A deliverable is generated in the current directory
- The runbook is checked for new discoveries

**Step 5: Export test**

Copy the contents of `runbook.md` and verify it pastes cleanly into a Google Doc with:
- Proper heading hierarchy
- Code blocks preserved
- No plugin-specific syntax in prose
- Clean checkbox formatting

**Step 6: Commit Clewfile**

```bash
cd ~
yadm add .claude/Clewfile.yaml
yadm commit -m "Add replicated-review plugin to Clewfile"
yadm push
```
