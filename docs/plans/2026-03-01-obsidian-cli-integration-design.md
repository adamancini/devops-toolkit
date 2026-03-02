# Obsidian CLI Integration Design

**Date:** 2026-03-01
**Status:** Approved
**Scope:** obsidian-notes agent + knowledge-reader agent

## Problem

The obsidian-notes and knowledge-reader agents currently use direct filesystem tools (Read, Grep, Glob) for all vault operations, with an optional REST API fallback. Obsidian v1.12 introduced an official CLI with 115+ commands that queries live indexes -- 54x faster than grep for search and 70,000x cheaper in tokens than MCP approaches. The agents should use the CLI as their primary interface when Obsidian is running.

## Design

### Three-Tier Interaction Model

**Tier 1: Obsidian CLI (preferred when available)**
- Detect once per session: `obsidian version 2>/dev/null`
- Use for all supported operations: search, read, create, append, properties, tags, tasks, backlinks, orphans
- Queries Obsidian's live in-memory indexes

**Tier 2: Direct Filesystem (always available)**
- Read/Write/Edit/Grep/Glob tools
- Used for: bulk operations, `.obsidian/` config, templates, vault structure, curated knowledge-base references, any operation when CLI unavailable

**Tier 3: REST API -- REMOVED**
- The `curl 127.0.0.1:27123` check is removed entirely. CLI supersedes it with better coverage and no plugin dependency.

### Operation Routing Table

| Operation | CLI Command | Filesystem Fallback |
|-----------|------------|-------------------|
| Search notes | `obsidian search query="..." format=json` | Grep |
| Read note content | `obsidian read path="..."` | Read tool |
| Create note | `obsidian create path="..." content="..." silent` | Write tool |
| Append to note | `obsidian append path="..." content="..."` | Edit tool |
| Set property | `obsidian property:set path="..." name="..." value="..."` | Edit tool (YAML) |
| Read property | `obsidian property:read path="..." name="..."` | Grep frontmatter |
| List tags | `obsidian tags counts sort=count` | Grep for tags |
| Find orphans | `obsidian orphans` | Manual link analysis |
| Find backlinks | `obsidian backlinks file="..."` | Grep for wikilinks |
| Unresolved links | `obsidian unresolved` | Grep + validate |
| Tasks | `obsidian tasks` | Grep for `- [ ]` |
| Daily note | `obsidian daily:read` / `daily:append` | Read/Edit journal/daily/ |
| MOC updates | Write/Edit tool (no CLI equivalent) | Write/Edit tool |
| Plugin config | Read/Edit tool (CLI for reload) | Read/Edit tool |
| Bulk operations | Grep/Glob + Edit | Grep/Glob + Edit |

### Files Modified

1. **`agents/obsidian-notes.md`** -- Replace Interaction Model section, update Search/Audit/MOC workflows, add CLI reference
2. **`agents/knowledge-reader.md`** -- Add Bash tool, add CLI detection, update search strategy with CLI commands

### No Changes To

- Frontmatter schema
- AI-optimized note structure
- Obsidian-flavored markdown reference
- Bases documentation
- Notion sync constraint/workflow
- Domain inference logic
- Self-check checklist
- Learn from URL workflow
- Template evolution
- Curated knowledge base integration

### knowledge-reader Tool Change

Add `Bash` to tool list (`tools: Read, Grep, Glob, LS, Bash`) to enable CLI search commands. Agent remains read-only by convention -- Bash used only for `obsidian search/read/tags/backlinks` queries.

## Implementation Steps

1. Edit `obsidian-notes.md`: Replace Interaction Model section with CLI-first model
2. Edit `obsidian-notes.md`: Update Search Knowledge Base workflow
3. Edit `obsidian-notes.md`: Update Vault Audit workflow
4. Edit `obsidian-notes.md`: Update Plugin Configuration and MOC Maintenance sections
5. Edit `obsidian-notes.md`: Add CLI documentation reference
6. Edit `knowledge-reader.md`: Add Bash to tools, add CLI detection and search strategy
7. Commit and push changes
