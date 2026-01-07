# Mutation Operations Reference

Detailed documentation for Linear MCP write operations.

## Linear:create_issue

**Purpose:** Create a new issue in Linear.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `title` | string | Yes | Issue title |
| `team` | string | Yes | Team name or ID |
| `description` | string | No | Markdown description |
| `project` | string | No | Project name or ID |
| `state` | string | No | Initial state (default: team's default) |
| `priority` | number | No | 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low |
| `assignee` | string | No | Assignee name, email, or "me" |
| `labels` | array | No | Array of label names |

**Example - Basic:**
```
Linear:create_issue {
  "title": "Fix login timeout issue",
  "team": "Annarchy-net",
  "description": "Users are experiencing timeouts when logging in."
}
```

**Example - Full:**
```
Linear:create_issue {
  "title": "Implement wiki-link resolution",
  "team": "Annarchy-net",
  "project": "Obsidian-Notion Sync",
  "description": "## Summary\n\nAdd support for resolving [[wiki-links]] to Notion page references.\n\n## Acceptance Criteria\n\n- [ ] Parse wiki-link syntax\n- [ ] Resolve to Notion page IDs\n- [ ] Handle unresolved links gracefully",
  "state": "Backlog",
  "priority": 3,
  "assignee": "me",
  "labels": ["enhancement", "backend"]
}
```

**Response Structure:**
```json
{
  "id": "new-issue-uuid",
  "identifier": "ANN-52",
  "title": "Fix login timeout issue",
  "state": {"name": "Backlog"},
  "url": "https://linear.app/team/issue/ANN-52"
}
```

**Validation:**
- Response must contain `identifier` matching pattern `[A-Z]+-[0-9]+`
- New identifier should be sequential (higher than previously seen)
- Store the returned `identifier` - this is the canonical reference

**Common Defaults:**
- If no `state`, uses team's default initial state (usually "Backlog")
- If no `priority`, defaults to None (0)
- If no `assignee`, issue is unassigned

---

## Linear:update_issue

**Purpose:** Modify an existing issue.

**Parameters:**
| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Issue identifier (e.g., "ANN-41") or UUID |
| `title` | string | No | New title |
| `description` | string | No | New description (replaces existing) |
| `state` | string | No | New state name |
| `priority` | number | No | New priority |
| `assignee` | string | No | New assignee (use null to unassign) |
| `project` | string | No | Move to different project |
| `labels` | array | No | Replace all labels |

**Example - Change State:**
```
Linear:update_issue {
  "id": "ANN-41",
  "state": "In Progress"
}
```

**Example - Multiple Fields:**
```
Linear:update_issue {
  "id": "ANN-41",
  "state": "Done",
  "description": "## Summary\n\nImplemented wiki-link resolution.\n\n## Changes\n\n- Added parser for [[wiki-link]] syntax\n- Integrated with Notion page lookup\n\n## Commits\n\n- efac3f9 fix: Resolve wiki-links for all pages"
}
```

**Example - Reassign:**
```
Linear:update_issue {
  "id": "ANN-41",
  "assignee": "me"
}
```

**Response Structure:**
```json
{
  "id": "issue-uuid",
  "identifier": "ANN-41",
  "title": "Issue title",
  "state": {"name": "In Progress"},
  "updatedAt": "2026-01-07T12:00:00.000Z"
}
```

**Validation:**
- Response `identifier` must match requested `id`
- Updated fields should reflect new values
- `updatedAt` should be recent (within last few seconds)

**State Transitions:**
Common Linear states and their types:
- `Backlog` - unstarted
- `Todo` - unstarted
- `In Progress` - started
- `In Review` - started
- `Done` - completed
- `Canceled` - canceled

---

## Mutation Best Practices

### Before Creating Issues

1. Verify the issue doesn't already exist (search first)
2. Use correct team name (run `list_teams` if unsure)
3. Include meaningful description with context

### Before Updating Issues

1. Fetch current issue state with `get_issue`
2. Only include fields you're changing
3. Verify the issue exists before updating

### After Mutations

Always verify the operation succeeded:
```
1. Check response contains expected identifier
2. Optionally: Fetch issue again to confirm changes
3. Report the new/updated identifier in your response
```

### Error Recovery

If mutation fails:
```
1. Check error message for cause
2. Verify parameters are correct (team exists, valid state name)
3. Retry once with corrected parameters
4. If still fails, report error to user
```
