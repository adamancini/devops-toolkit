---
topic: obsidian-automation
source: https://help.obsidian.md/cli
created: 2026-03-01
updated: 2026-03-01
tags:
  - obsidian
  - cli
  - automation
  - ai-agent
---

# Obsidian CLI (Official, v1.12+)

## Summary

The official Obsidian CLI, released in v1.12 (February 2026), provides 115+ commands for terminal-based control of a running Obsidian desktop instance via IPC. It queries Obsidian's live indexes (search, link graph, tags, properties), making it 54x faster than grep for search and 70,000x cheaper in token cost than MCP-based approaches for AI agent workflows.

## Key Concepts

### Architecture

- Communicates with a running Obsidian desktop instance via IPC -- not direct filesystem access
- Queries the same in-memory indexes that power the GUI (Cmd+Shift+F, backlinks, graph view)
- Obsidian must be running; first CLI command launches the app if needed
- On headless Linux: use `.deb` package + Xvfb (`xvfb-run --auto-servernum obsidian --no-sandbox`)

### Setup

1. Update Obsidian to v1.12+ (installer v1.11.7+, app v1.12.x)
2. Enable CLI: Settings > General > Command line interface
3. Follow prompt to register in system PATH

**Platform PATH details:**
- macOS: adds to `~/.zprofile`: `export PATH="$PATH:/Applications/Obsidian.app/Contents/MacOS"`
- Linux: symlink at `/usr/local/bin/obsidian` (sudo) or `~/.local/bin/obsidian` (fallback)
- Windows: requires `Obsidian.com` redirector alongside `Obsidian.exe`, must run non-admin

### Licensing

Early Access required Catalyst License ($25 one-time). As of v1.12.4 (Feb 27, 2026) it shipped as a public build. Planned to be free for all users.

### Syntax Conventions

- Parameters: `key=value` syntax. Quote values with spaces: `name="My Note"`
- Multiline content: `\n` for newline, `\t` for tab
- `file=<name>` resolves like a wikilink (name only, no path/extension)
- `path=<path>` is vault-relative exact path (e.g., `folder/note.md`)
- Without `file` or `path`, the active file is used
- `vault=<name>` as first parameter targets a specific vault
- `--copy` copies output to clipboard
- `format=json|tsv|csv` for structured output
- `total` on list commands returns count only
- `open` opens the target file; default is silent (v1.12.2+)

## Command Reference

### File Operations

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `read` | Read note content | `file=`, `path=` |
| `create` | Create a note | `name=`, `path=` (omit `.md`), `content=`, `template=`, `open`, `overwrite` |
| `append` | Append to note | `file=`, `path=`, `content=` |
| `prepend` | Prepend after frontmatter | `file=`, `path=`, `content=` |
| `move` | Move a note | `file=`, `path=`, `name=` (target path with `.md`) |
| `rename` | Rename a note | `file=`, `path=`, `name=` |
| `delete` | Delete a note | `file=`, `path=`, `permanent` (skip trash) |
| `files` | List vault files | `path=<folder>`, `format=`, `total` |

### Daily Notes

| Command | Description |
|---------|-------------|
| `daily` | Open today's daily note |
| `daily:read` | Print daily note content |
| `daily:append content="..."` | Append to daily note |
| `daily:prepend content="..."` | Prepend after frontmatter |
| `daily:path` | Get expected daily note path |

### Search

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `search` | Full-text search, returns file paths | `query=` (required), `path=`, `limit=`, `format=text|json`, `total`, `case` |
| `search:context` | Grep-style with line context | `query=`, `path=`, `limit=`, `format=`, `case` |
| `search:open` | Open search view in GUI | `query=` |

### Properties (Frontmatter)

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `properties` | List all properties of a note | `file=`, `path=`, `format=` |
| `property:set` | Set a property | `file=`, `path=`, `name=`, `value=` |
| `property:read` | Read a property value | `file=`, `path=`, `name=` |
| `property:remove` | Remove a property | `file=`, `path=`, `name=` |

### Tags

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `tags` | List tags | `file=`, `path=`, `sort=count`, `total`, `counts`, `format=`, `active` |
| `tag` | Files with a specific tag | `name=` |

### Tasks

| Command | Description |
|---------|-------------|
| `tasks` | All incomplete tasks |
| `tasks all` | All tasks |
| `tasks done` | Completed only |
| `tasks daily` | Tasks in today's daily note |
| `task path="..." line=N toggle` | Toggle a specific task |

### Links

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `backlinks` | Backlinks for a note | `file=`, `path=` |
| `orphans` | Files with no incoming links | `total`, `format=` |
| `unresolved` | Broken/unresolved links | `total`, `counts`, `verbose`, `format=` |

### Sync

| Command | Description |
|---------|-------------|
| `sync:status` | Sync status and usage |
| `sync:pause` / `sync:resume` | Pause/resume sync |
| `sync:history path="..."` | Version history for a file |
| `sync:restore path="..." version=N` | Restore a version |
| `sync:deleted` | List deleted files in sync |

### Developer Tools

| Command | Description | Key Parameters |
|---------|-------------|----------------|
| `eval` | Run JS against Obsidian API | `code=` (required) |
| `dev:screenshot` | Take screenshot | `path=<filename>` |
| `dev:console` | Console messages | `limit=`, `level=`, `clear` |
| `dev:errors` | JS errors | `clear` |
| `dev:css` | Inspect CSS | `selector=`, `prop=` |
| `dev:dom` | Query DOM elements | `selector=`, `attr=`, `text`, `inner`, `all` |
| `devtools` | Toggle Electron dev tools | |
| `plugin:reload` | Reload a plugin | `id=` |

### Other Commands

| Command | Description |
|---------|-------------|
| `bookmarks` | Bookmark management |
| `outline` | Show headings (`format=tree|md|json`) |
| `random` | Open random note |
| `command id="..."` | Execute a command palette command |
| `commands` | List available command IDs |
| `hotkeys` | List hotkeys |
| `plugins` | List installed plugins (`core|community`, `format=`) |
| `help` / `help <command>` | Help reference |

## AI Agent Integration Patterns

### Tiered Access Model (Prokopov)

| Access Method | Vault Coverage | Requires Running Obsidian |
|---------------|---------------|---------------------------|
| Filesystem (Read/Grep/Glob) | ~40% | No |
| REST API plugin (127.0.0.1:27123) | ~55% | Yes |
| **Official CLI** | **~85%** | **Yes** |
| GUI only (canvas, graph animation) | 100% | Yes |

### Claude Code Integration

The CLI works natively with Claude Code via Bash tool. Recommended agent instructions:

```
Use `obsidian` CLI for vault queries instead of grep/find.
Prefer `obsidian search` over filesystem scanning.
Use `obsidian backlinks` and `obsidian orphans` for graph queries.
Use `obsidian property:read/set` for frontmatter instead of parsing YAML.
Use format=json for machine-parseable output.
```

### Performance Benchmarks (4,663 file vault)

| Operation | grep | CLI | Speedup |
|-----------|------|-----|---------|
| Search | 1.95s | 0.32s | 6x |
| Orphan detection | 15.6s | 0.26s | 54x |
| Token cost (MCP approach) | ~7M tokens | ~100 tokens | 70,000x |

### TUI Mode

Running `obsidian` with no arguments launches an interactive TUI with autocomplete, command history, and reverse search (Ctrl+R). Inside TUI, omit the `obsidian` prefix.

## Decision Points

**Use CLI when:** Obsidian is running (desktop/Xvfb), need search/graph/metadata queries, AI agent workflows, automation scripts.

**Use direct filesystem when:** Obsidian not running, headless server without Xvfb, simple file read/write, CI pipelines without GUI.

**Use Obsidian Headless when:** Need sync only (no queries), server deployment, CI/CD vault sync.

## Version History (CLI-specific)

- **v1.12.0** (Feb 10, 2026): Initial release
- **v1.12.2**: Added `help <cmd>`, `daily:path`, `rename`, `search:context`; defaults to silent; `active`/`open` replace `all`/`silent`
- **v1.12.3**: Fixed CLI hanging for longer content
- **v1.12.4** (Feb 27, 2026): Public build; Windows CLI detection fix

## References

- [Official CLI Docs](https://help.obsidian.md/cli) -- canonical, always up-to-date
- [Obsidian 1.12 Changelog](https://obsidian.md/changelog/2026-02-27-desktop-v1.12.4/)
- [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) -- agent skill definitions
- [Prokopov: 70,000x Cheaper AI Agents](https://prokopov.me/posts/obsidian-cli-changes-everything-for-ai-agents/)
- [Retype Docs Mirror](https://retypeapp.github.io/obsidian/cli/)
- [Windows Setup Guide](https://zenn.dev/sora_biz/articles/obsidian-cli-setup-guide?locale=en)
- Obsidian vault note: `~/notes/reference/Obsidian CLI Reference.md`
