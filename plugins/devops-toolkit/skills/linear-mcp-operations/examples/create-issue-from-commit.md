# Example: Create Issue from Commit

Complete workflow for creating a Linear issue to document completed work.

## Scenario

User has made commits and wants to create/update a Linear issue:
```
efac3f9 fix: Resolve wiki-links for all pages with links in second pass
8078e26 feat: Enhance status command with wiki-link statistics
```

## Workflow

### Step 1: Health Check

```
Linear:list_teams {}
```

**Validation:** Response contains teams → Proceed

### Step 2: Search for Existing Issue (Optional)

If user mentions this relates to existing work:
```
Linear:search {"query": "wiki-link resolution"}
```

Check if an issue already exists that should be updated instead of creating new.

### Step 3: Create Issue

```
Linear:create_issue {
  "title": "Two-pass wiki-link resolution for forward references",
  "team": "Annarchy-net",
  "project": "Obsidian-Notion Sync",
  "state": "Done",
  "description": "## Summary\n\nImplemented two-pass wiki-link resolution to handle forward references where page A links to page B, but B is processed after A.\n\n## Changes\n\n- Modified second pass to include ALL pages with wiki-links, not just new ones\n- Added `checkForNewlyResolvedLinks()` helper to detect new resolutions\n- Enhanced status command with wiki-link statistics\n\n## Commits\n\n- `efac3f9` fix: Resolve wiki-links for all pages with links in second pass\n- `8078e26` feat: Enhance status command with wiki-link statistics\n\n## Testing\n\n- Added tests for forward reference scenarios\n- Verified with circular reference edge cases",
  "labels": ["enhancement", "backend"]
}
```

### Step 4: Validate Response

**Expected Response:**
```json
{
  "id": "new-uuid",
  "identifier": "ANN-52",
  "title": "Two-pass wiki-link resolution for forward references",
  "state": {"name": "Done"},
  "url": "https://linear.app/annarchy/issue/ANN-52"
}
```

**Validation:**
- [ ] Response contains `identifier`
- [ ] Identifier matches pattern `ANN-[0-9]+`
- [ ] Identifier is new (higher than previously known max)

### Step 5: Format Output

```markdown
## Created: ANN-52

**Title:** Two-pass wiki-link resolution for forward references
**Status:** Done
**URL:** https://linear.app/annarchy/issue/ANN-52

---
mcp_status: connected
tools_called: [Linear:list_teams, Linear:create_issue]
validation: passed
---
```

## Variation: Update Existing Issue

If an issue already exists (e.g., ANN-47) that should be updated:

### Step 3 (Alternative): Update Issue

```
Linear:update_issue {
  "id": "ANN-47",
  "state": "Done",
  "description": "## Summary\n\n[Updated description with completion details]\n\n## Commits\n\n- `efac3f9` fix: Resolve wiki-links\n- `8078e26` feat: Enhance status command"
}
```

### Output for Update

```markdown
## Updated: ANN-47

**Status:** Done
**Changes:** Added completion details and commit references

---
mcp_status: connected
tools_called: [Linear:list_teams, Linear:get_issue, Linear:update_issue]
validation: passed
---
```

## Important Notes

1. **Always verify issue doesn't already exist** before creating
2. **Use real commit hashes** from git log, never fabricate
3. **Include meaningful description** with context for future reference
4. **Set state appropriately** - if work is done, mark as Done
