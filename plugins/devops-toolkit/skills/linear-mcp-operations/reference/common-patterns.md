# Common Patterns

Frequently used patterns and workflows for Linear MCP operations.

## Filtering Issues

### By State

```
# Get all backlog items
Linear:list_issues {"state": "Backlog"}

# Get active work
Linear:list_issues {"state": "In Progress"}

# Get completed issues
Linear:list_issues {"state": "Done"}
```

### By Project

```
# All issues for a specific project
Linear:list_issues {"project": "Obsidian-Notion Sync"}

# Backlog for a specific project
Linear:list_issues {
  "project": "Obsidian-Notion Sync",
  "state": "Backlog"
}
```

### By Assignee

```
# My assigned issues
Linear:list_issues {"assignee": "me"}

# My in-progress work
Linear:list_issues {
  "assignee": "me",
  "state": "In Progress"
}
```

### Combined Filters

```
# My backlog items in a specific project
Linear:list_issues {
  "project": "Obsidian-Notion Sync",
  "assignee": "me",
  "state": "Backlog"
}
```

## Issue Lifecycle Workflows

### Start Working on an Issue

```
1. Linear:list_teams {}  # Health check
2. Linear:get_issue {"id": "ANN-41"}  # Get current state
3. Linear:update_issue {"id": "ANN-41", "state": "In Progress", "assignee": "me"}
```

### Complete an Issue

```
1. Linear:list_teams {}  # Health check
2. Linear:update_issue {
     "id": "ANN-41",
     "state": "Done",
     "description": "## Summary\n\n[What was done]\n\n## Commits\n\n- [commit hash] [message]"
   }
```

### Create and Start Issue

```
1. Linear:list_teams {}  # Health check
2. Linear:create_issue {
     "title": "New feature",
     "team": "Annarchy-net",
     "project": "Obsidian-Notion Sync",
     "state": "In Progress",
     "assignee": "me"
   }
```

## Bulk Operations

### Get All Issues for Sprint Planning

```
1. Linear:list_teams {}  # Health check
2. Linear:list_issues {
     "project": "Obsidian-Notion Sync",
     "state": "Backlog"
   }
3. For each issue, optionally get full details:
   Linear:get_issue {"id": "ANN-XX"}
```

### Update Multiple Issues to Done

For each issue to close:
```
Linear:update_issue {"id": "ANN-XX", "state": "Done"}
```

Report each update result before proceeding to next.

## Search Patterns

### Find Related Issues

```
# Search by keyword
Linear:search {"query": "authentication"}

# Search in specific team
Linear:search {"query": "wiki-link", "team": "Annarchy-net"}
```

### Find Issue by Partial Information

When you know some details but not the identifier:
```
1. Linear:search {"query": "login timeout"}
2. Review results to find correct issue
3. Linear:get_issue {"id": "found-identifier"}
```

## Error Recovery Patterns

### Retry with Backoff

If a tool call fails:
```
1. First attempt: Call tool
2. If error: Wait briefly, retry once
3. If still error: Report failure, do not guess
```

### Handle "Issue Not Found"

```
1. Verify identifier format is correct (ANN-XX)
2. Search for issue by title/description
3. If found with different ID, use correct ID
4. If not found, report issue does not exist
```

### Handle "Team Not Found"

```
1. Run Linear:list_teams to get valid teams
2. Match user's team name to available options
3. Retry with correct team name/ID
```

## Formatting Patterns

### Description Template for Features

```markdown
## Summary

[1-2 sentence overview]

## Requirements

- [ ] Requirement 1
- [ ] Requirement 2

## Acceptance Criteria

- [ ] Criteria 1
- [ ] Criteria 2

## Notes

[Additional context]
```

### Description Template for Bugs

```markdown
## Problem

[What's broken]

## Steps to Reproduce

1. Step one
2. Step two

## Expected Behavior

[What should happen]

## Actual Behavior

[What actually happens]
```

### Description Template for Completed Work

```markdown
## Summary

[What was accomplished]

## Changes

- Change 1
- Change 2

## Commits

- [hash] [message]
- [hash] [message]

## Testing

[How it was tested]
```
