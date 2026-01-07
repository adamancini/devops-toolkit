# Query Operations Reference

Detailed documentation for Linear MCP read operations.

## Linear:list_teams

**Purpose:** Health check and team discovery. Always call first.

**Parameters:** None required

**Example:**
```
Linear:list_teams {}
```

**Response Structure:**
```json
{
  "teams": [
    {
      "id": "team-uuid",
      "name": "Engineering",
      "key": "ENG"
    }
  ]
}
```

**Use for:**
- Health check (verify MCP is responding)
- Discovering team IDs for filtering
- Getting team keys for issue prefixes

---

## Linear:list_issues

**Purpose:** Query issues with optional filters.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `team` | string | Team name or ID to filter by |
| `project` | string | Project name or ID to filter by |
| `state` | string | Issue state: "Backlog", "Todo", "In Progress", "Done", "Canceled" |
| `assignee` | string | Assignee name, email, or "me" |
| `limit` | number | Max results (default varies) |

**Examples:**

List all backlog issues for a project:
```
Linear:list_issues {
  "project": "Obsidian-Notion Sync",
  "state": "Backlog"
}
```

List issues assigned to me:
```
Linear:list_issues {
  "assignee": "me",
  "state": "In Progress"
}
```

List all issues for a team:
```
Linear:list_issues {
  "team": "Annarchy-net"
}
```

**Response Structure:**
```json
{
  "issues": [
    {
      "id": "issue-uuid",
      "identifier": "ANN-41",
      "title": "Issue title here",
      "description": "Description text...",
      "state": {"name": "In Progress"},
      "priority": 2,
      "assignee": {"name": "Ada"},
      "project": {"name": "Project Name"},
      "createdAt": "2026-01-01T00:00:00.000Z",
      "updatedAt": "2026-01-05T00:00:00.000Z"
    }
  ]
}
```

**Validation:**
- Each issue must have `id`, `identifier`, `title`
- `identifier` must match pattern `[A-Z]+-[0-9]+`
- If empty array returned, confirm no matching issues (not an error)

---

## Linear:get_issue

**Purpose:** Fetch detailed information for a single issue.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `id` | string | Issue identifier (e.g., "ANN-41") or UUID |

**Example:**
```
Linear:get_issue {
  "id": "ANN-41"
}
```

**Response Structure:**
```json
{
  "id": "issue-uuid",
  "identifier": "ANN-41",
  "title": "Issue title",
  "description": "Full description with markdown...",
  "state": {"name": "In Progress", "type": "started"},
  "priority": 2,
  "priorityLabel": "Medium",
  "assignee": {
    "id": "user-uuid",
    "name": "Ada",
    "email": "ada@example.com"
  },
  "project": {
    "id": "project-uuid",
    "name": "Obsidian-Notion Sync"
  },
  "team": {
    "id": "team-uuid",
    "name": "Annarchy-net",
    "key": "ANN"
  },
  "labels": [
    {"name": "bug"},
    {"name": "backend"}
  ],
  "createdAt": "2026-01-01T00:00:00.000Z",
  "updatedAt": "2026-01-05T00:00:00.000Z",
  "url": "https://linear.app/team/issue/ANN-41"
}
```

**Validation:**
- Response must not be null or error
- `identifier` in response must match requested ID
- If issue not found, Linear returns error (not empty object)

---

## Linear:search

**Purpose:** Full-text search across issues, projects, and documents.

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `query` | string | Search terms |
| `team` | string | Optional team filter |

**Example:**
```
Linear:search {
  "query": "authentication bug"
}
```

**Response Structure:**
```json
{
  "results": [
    {
      "type": "issue",
      "id": "issue-uuid",
      "identifier": "ANN-35",
      "title": "Fix authentication token refresh",
      "description": "Bug in token refresh logic..."
    }
  ]
}
```

**Use for:**
- Finding issues by keyword when identifier unknown
- Discovering related issues
- Searching across all content
