---
description: Contribute runbook and reference doc updates back to devops-toolkit via PR
allowed-tools: ["Read", "Grep", "Glob", "Bash", "AskUserQuestion"]
---

# Contribute Runbook

Contribute runbook and reference doc changes back to the shared devops-toolkit repository via a GitHub PR (or patch export if `gh` CLI is unavailable).

## Execution

### Step 1 - Navigate to Marketplace Root

The marketplace repo root is two levels up from the plugin root:

```bash
cd ${CLAUDE_PLUGIN_ROOT}/../../
```

This should be the `devops-toolkit` marketplace clone. Verify by checking that `.git/` exists and the remote points to `adamancini/devops-toolkit`.

### Step 2 - Fetch Latest Origin

```bash
git fetch origin
```

### Step 3 - Check for Changes

Diff the in-scope files against `origin/main`:

```bash
git diff origin/main -- plugins/replicated-review/skills/release-review/
```

**In-scope files:**
- `plugins/replicated-review/skills/release-review/runbook.md`
- `plugins/replicated-review/skills/release-review/reference/*.md`

If the diff is empty, report:

> Nothing to contribute. The runbook and reference docs match origin/main.

Then **stop** -- do not proceed further.

### Step 4 - Show Summary

Show the user a summary of what will be contributed:

```bash
git diff --stat origin/main -- plugins/replicated-review/skills/release-review/
```

List each changed file with added/removed line counts.

### Step 5 - Confirm with User

Ask the user to confirm before proceeding:

> The above changes will be contributed back to adamancini/devops-toolkit. Proceed?

Use AskUserQuestion with options:
- **Yes, open a PR** -- continue with PR workflow
- **No, cancel** -- abort without making changes

If the user cancels, stop immediately.

### Step 6 - Create a Contribution Branch

Generate a date-stamped branch name:

```bash
BRANCH_NAME="runbook/contribute-$(date +%Y-%m-%d)"
git checkout -b "$BRANCH_NAME"
```

### Step 7 - Stage and Commit

Stage only the in-scope files:

```bash
git add plugins/replicated-review/skills/release-review/
git commit -m "docs(runbook): contribute findings from review"
```

### Step 8 - Check for gh CLI

```bash
which gh
```

**If `gh` is available:** proceed to Step 9 (PR workflow).
**If `gh` is NOT available:** skip to Step 10 (patch workflow).

### Step 9 - PR Workflow (gh available)

#### 9a - Fork the Repository

```bash
gh repo fork adamancini/devops-toolkit --clone=false
```

This is idempotent -- it succeeds whether or not a fork already exists.

#### 9b - Determine Fork Remote

Check existing remotes for the fork:

```bash
git remote -v
```

Look for a remote pointing to the user's fork of `devops-toolkit`. The `gh repo fork` command typically adds a remote named after the user's GitHub handle, or `origin` may have been updated. If no fork remote is found, add one:

```bash
GITHUB_USER=$(gh api user --jq '.login')
git remote add fork "https://github.com/$GITHUB_USER/devops-toolkit.git" 2>/dev/null || true
```

Use whichever remote name points to the fork (commonly the user's GitHub username or `fork`).

#### 9c - Push the Branch

```bash
git push <fork-remote> "$BRANCH_NAME"
```

#### 9d - Open the PR

```bash
gh pr create \
  --repo adamancini/devops-toolkit \
  --head "$GITHUB_USER:$BRANCH_NAME" \
  --title "docs(runbook): contribute review findings" \
  --body "$(cat <<'PRBODY'
## Runbook Contribution

Findings contributed on YYYY-MM-DD.

### Changed files
(list each changed file with +/- line counts from git diff --stat)

### Summary
(auto-generated bullet list describing what was added/changed)
PRBODY
)"
```

Replace `YYYY-MM-DD` with today's date and fill in the changed files list and summary from the diff output gathered in Step 4.

Report the PR URL to the user.

#### 9e - Skip to Step 11

### Step 10 - Patch Workflow (gh not available)

Generate patch files from the contribution:

```bash
git format-patch origin/main -- plugins/replicated-review/skills/release-review/
```

Copy the patch file(s) to the user's home directory:

```bash
cp *.patch ~/runbook-contribution-$(date +%Y-%m-%d).patch
```

Report the patch location and provide manual submission instructions:

> Patch exported to `~/runbook-contribution-YYYY-MM-DD.patch`.
>
> To submit manually:
> 1. Fork https://github.com/adamancini/devops-toolkit on GitHub
> 2. Clone your fork locally
> 3. Apply the patch: `git am ~/runbook-contribution-YYYY-MM-DD.patch`
> 4. Push and open a PR against `adamancini/devops-toolkit:main`

### Step 11 - Clean Up

Reset the marketplace clone back to a clean state:

```bash
git checkout main
git reset --hard origin/main
```

This ensures the local clone stays in sync with origin and does not retain the contribution branch locally.

### Step 12 - Report

Provide a final summary:

- Whether a PR was opened (with URL) or a patch was exported (with path)
- Remind the user that changes will be available to other team members after the PR is merged and they refresh the plugin
