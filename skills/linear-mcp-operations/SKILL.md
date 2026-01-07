---
name: linear-mcp-operations
description: Reliable Linear MCP operations with mandatory health checking and response validation. Use when interacting with Linear for issues, projects, teams, or cycles. Ensures MCP connectivity before operations and validates responses to prevent hallucination of issue numbers or stale data.
---

# Linear MCP Operations

Provides reliable, validated access to Linear via MCP. This skill enforces health checks and response validation to prevent common failure modes like hallucinated issue IDs or operating on stale context data.

## CRITICAL: Why This Skill Exists

Without proper validation, Linear operations fail silently:
- **Hallucinated IDs**: Responding with issue numbers that don't exist (e.g., ANN-99 when max is ANN-50)
- **Stale context**: Using issue data from conversation history instead of querying Linear
- **MCP unavailable**: Attempting operations when Linear MCP server is down

**This skill prevents these failures through mandatory protocols.**

## Health Check Protocol (MANDATORY FIRST STEP)

**BEFORE ANY LINEAR OPERATION**, verify MCP connectivity:

```
1. Call Linear:list_teams with no parameters
2. Verify response contains team data with valid IDs
3. If error or empty response:
   → STOP immediately
   → Report: "Linear MCP unavailable - cannot proceed"
   → Do NOT attempt to answer from context
4. Only proceed to requested operation if health check passes
```

### Health Check Example

```
Linear:list_teams {}

Expected response structure:
{
  "teams": [
    {"id": "uuid-here", "name": "Team Name", "key": "TEAM"}
  ]
}

If response is error or empty → MCP is unavailable
If response has teams → Proceed with requested operation
```

## Operation Workflows

### Query Operations (Reading Data)

For fetching issues, projects, or other data:

1. **Health check** - Run `Linear:list_teams` first
2. **Execute query** - See [reference/query-operations.md](reference/query-operations.md)
3. **Validate response** - Verify IDs match format `[A-Z]+-[0-9]+`
4. **Report status** - Include tools_called and mcp_status

### Mutation Operations (Writing Data)

For creating or updating issues:

1. **Health check** - Run `Linear:list_teams` first
2. **Execute mutation** - See [reference/mutation-operations.md](reference/mutation-operations.md)
3. **Verify result** - Confirm returned identifier matches expected format
4. **Report status** - Include tools_called, identifier, and mcp_status

## Response Validation Checklist

After EVERY Linear tool call, verify:

- [ ] Response is not empty or null
- [ ] Issue IDs follow format: `[A-Z]+-[0-9]+` (e.g., ANN-41, PROJ-123)
- [ ] Required fields present:
  - Issues: `id`, `identifier`, `title`, `state`
  - Projects: `id`, `name`
  - Teams: `id`, `name`, `key`
- [ ] Timestamps are valid ISO dates (not obviously wrong like year 1970)

**If validation fails:**
1. Re-run the tool call once
2. If still fails, report error with details
3. NEVER fabricate or guess data

## Available Tools

| Tool | Purpose | Reference |
|------|---------|-----------|
| `Linear:list_teams` | Health check, list teams | [query-operations.md](reference/query-operations.md) |
| `Linear:list_issues` | Query issues with filters | [query-operations.md](reference/query-operations.md) |
| `Linear:get_issue` | Fetch single issue by ID | [query-operations.md](reference/query-operations.md) |
| `Linear:search` | Full-text search | [query-operations.md](reference/query-operations.md) |
| `Linear:create_issue` | Create new issue | [mutation-operations.md](reference/mutation-operations.md) |
| `Linear:update_issue` | Modify existing issue | [mutation-operations.md](reference/mutation-operations.md) |

For detailed parameters and examples, see the reference files.

## Status Reporting

**Every response MUST end with a status block:**

```
---
mcp_status: connected | error | unavailable
tools_called: [Linear:list_teams, Linear:get_issue]
records_returned: N
validation: passed | failed
---
```

This enables debugging and confirms actual tool usage.

## Error Handling

### MCP Unavailable

```
## Linear MCP Unavailable

Health check failed - Linear MCP server is not responding.

**Attempted:** Linear:list_teams
**Result:** [error message or empty response]

Cannot proceed with Linear operations. Please:
1. Verify Linear MCP plugin is enabled
2. Check Linear API status
3. Try again in a few minutes

---
mcp_status: unavailable
tools_called: [Linear:list_teams]
---
```

### Invalid Response

```
## Linear Response Invalid

Received malformed data from Linear API.

**Tool:** Linear:get_issue
**Issue:** Response missing required field 'identifier'

Retrying once...
[If retry also fails, report and stop]

---
mcp_status: error
tools_called: [Linear:list_teams, Linear:get_issue]
validation: failed
---
```

## Common Patterns

See [reference/common-patterns.md](reference/common-patterns.md) for:
- Filtering issues by state (Backlog, In Progress, Done)
- Filtering by project or assignee
- Pagination for large result sets
- Bulk operations

## Examples

See [examples/](examples/) for complete workflows:
- [examples/fetch-project-backlog.md](examples/fetch-project-backlog.md) - Get all backlog issues for a project
- [examples/create-issue-from-commit.md](examples/create-issue-from-commit.md) - Create issue linked to commit
