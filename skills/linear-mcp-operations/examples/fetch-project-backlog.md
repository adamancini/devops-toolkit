# Example: Fetch Project Backlog

Complete workflow for fetching all backlog issues for a project.

## Scenario

User asks: "What's in the backlog for Obsidian-Notion Sync?"

## Workflow

### Step 1: Health Check

```
Linear:list_teams {}
```

**Expected Response:**
```json
{
  "teams": [
    {"id": "uuid", "name": "Annarchy-net", "key": "ANN"}
  ]
}
```

**Validation:** Response contains at least one team → Proceed

### Step 2: Query Backlog Issues

```
Linear:list_issues {
  "project": "Obsidian-Notion Sync",
  "state": "Backlog"
}
```

**Expected Response:**
```json
{
  "issues": [
    {
      "id": "uuid-1",
      "identifier": "ANN-55",
      "title": "Add support for callout blocks",
      "priority": 3,
      "state": {"name": "Backlog"}
    },
    {
      "id": "uuid-2",
      "identifier": "ANN-54",
      "title": "Implement bidirectional sync",
      "priority": 2,
      "state": {"name": "Backlog"}
    }
  ]
}
```

### Step 3: Validate Response

- [ ] Response is not empty
- [ ] Each issue has `identifier` matching `[A-Z]+-[0-9]+`
- [ ] All issues show `state.name` = "Backlog"
- [ ] Issue identifiers are plausible (not higher than expected max)

### Step 4: Format Output

```markdown
## Backlog: Obsidian-Notion Sync

| ID | Title | Priority |
|----|-------|----------|
| ANN-55 | Add support for callout blocks | Medium |
| ANN-54 | Implement bidirectional sync | High |

**Total:** 2 issues

---
mcp_status: connected
tools_called: [Linear:list_teams, Linear:list_issues]
records_returned: 2
validation: passed
---
```

## Error Scenarios

### No Issues Found

If `issues` array is empty:
```markdown
## Backlog: Obsidian-Notion Sync

No backlog issues found for this project.

---
mcp_status: connected
tools_called: [Linear:list_teams, Linear:list_issues]
records_returned: 0
validation: passed
---
```

### Project Not Found

If error mentions project not found:
```markdown
## Error

Project "Obsidian-Notion Sync" not found in Linear.

Please verify:
1. Project name is spelled correctly
2. You have access to this project

---
mcp_status: connected
tools_called: [Linear:list_teams, Linear:list_issues]
validation: failed
---
```
