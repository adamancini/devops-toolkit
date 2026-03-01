---
topic: obsidian-automation
source: https://help.obsidian.md/uri
created: 2026-03-01
updated: 2026-03-01
tags:
  - obsidian
  - uri
  - automation
  - x-callback-url
---

# Obsidian URI Protocol

## Summary

Obsidian registers the `obsidian://` URI scheme for inter-app communication and automation. The native protocol supports four built-in actions (`open`, `search`, `new`, `daily`), while community plugins -- notably Advanced URI and Actions URI -- expand capabilities to cover file manipulation, command execution, frontmatter editing, search-and-replace, workspace management, and plugin control. URIs work cross-platform (macOS, Windows, Linux, iOS, Android) and are ideal for mobile automation, Shortcuts, and cross-app integrations where the CLI is unavailable.

## Key Concepts

### Native Actions (Built-in)

#### `open` -- Open vault/file

```
obsidian://open?vault=VAULT&file=FILE
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `vault` | Yes (unless `path`) | Vault name or 16-char vault ID |
| `file` | No | File name or path (wikilink resolution, `.md` optional) |
| `path` | No | Globally absolute path (overrides `vault` and `file`) |

#### `search` -- Open search pane

```
obsidian://search?vault=VAULT&query=QUERY
```

#### `new` -- Create a note

```
obsidian://new?vault=VAULT&name=NAME&content=CONTENT
```

| Parameter | Description |
|-----------|-------------|
| `name` | File name (uses "Default location for new notes" preference) |
| `file` | Vault-absolute path (overrides `name`) |
| `content` | Body content |
| `append` | Append to existing file, merge properties |
| `prepend` | Prepend to existing file, merge properties |
| `overwrite` | Overwrite existing file (flag, no value) |
| `silent` | Don't open the note (flag, no value) |

#### `daily` -- Open daily note (v1.7.2+)

```
obsidian://daily?vault=VAULT
```

### Advanced URI Plugin (Vinzent03)

The most comprehensive URI automation plugin. Base URL: `obsidian://adv-uri?`

#### File Identification (mutually exclusive)

| Parameter | Description |
|-----------|-------------|
| `filepath` | Vault-relative path (`.md` optional) |
| `filename` | File name (resolves via aliases) |
| `uid` | Unique frontmatter identifier |
| `daily` | `true` to target today's daily note |

#### Navigation

| Parameter | Description |
|-----------|-------------|
| `heading` | Navigate to heading |
| `block` | Navigate to block ID |
| `line` | Navigate to line number |
| `viewmode` | `source`, `preview`, or `live` |
| `openmode` | `true` (new pane), `tab`, `split`, `right`, `window`, `popover` |

#### Writing

| Parameter | Description |
|-----------|-------------|
| `data` | Content to write |
| `clipboard` | `true` to use clipboard contents |
| `mode` | `append`, `prepend`, `overwrite`, `new` |
| `heading` | Target heading for append/prepend |
| `line` | Target line for append/prepend |

#### Search and Replace

```
obsidian://adv-uri?filepath=FILE&search=OLD&replace=NEW
obsidian://adv-uri?filepath=FILE&searchregex=PATTERN&replace=NEW
```

#### Frontmatter

| Parameter | Description |
|-----------|-------------|
| `frontmatterkey` | Key to read/write. Nesting: `[key1,key2]`, arrays: `[key1,0]` |
| `data` | Value to write (string, number, boolean, list, JSON) |

Reading copies value to clipboard. Writing creates key if missing.

#### Command Execution

```
obsidian://adv-uri?commandid=COMMAND_ID
obsidian://adv-uri?commandname=COMMAND_NAME
```

Use `commandid` (stable) over `commandname` (may change).

#### Workspace and Bookmarks

```
obsidian://adv-uri?workspace=WORKSPACE_NAME&saveworkspace=true
obsidian://adv-uri?bookmark=BOOKMARK_NAME
```

#### Plugin Management

```
obsidian://adv-uri?enable-plugin=PLUGIN_ID
obsidian://adv-uri?disable-plugin=PLUGIN_ID
```

#### Settings Navigation

```
obsidian://adv-uri?settingid=editor&settingsection=Behavior
```

### Actions URI Plugin (czottmann)

REST-like structured endpoints under `obsidian://actions-uri/`. Full x-callback-url support on every route.

#### Route Groups

| Route | Description |
|-------|-------------|
| `/note/*` | Note CRUD (list, get, create, append, prepend, rename, move, delete) |
| `/note-properties/*` | Frontmatter set/clear/remove-keys |
| `/command/*` | List and execute commands |
| `/dataview/*` | Run DQL queries (LIST, TABLE) |
| `/search/*` | Search vault |
| `/omnisearch/*` | Omnisearch plugin integration |
| `/vault/*` | Vault open/close/info |
| `/folder/*` | Folder CRUD |
| `/file/*` | Non-note file operations |
| `/tags/*` | Tag reading |
| `/info/*` | Plugin/environment info |

## Practical Application

### macOS Command Line

```bash
# Open a vault
open "obsidian://open?vault=MyVault"

# Create note with content
open "obsidian://new?vault=MyVault&name=Inbox&content=Hello%20World"

# Append to daily note (background, no focus steal)
open --background "obsidian://adv-uri?vault=MyVault&daily=true&clipboard=true&mode=append"

# Execute a command
open "obsidian://adv-uri?vault=MyVault&commandid=workspace:export-pdf"
```

### Linux

```bash
# IMPORTANT: values must be double-encoded for xdg-open
xdg-open "obsidian://advanced-uri?filepath=Home%2520Index%252Ftoday"
```

### Windows

```powershell
Start-Process "obsidian://open?vault=MyVault&file=MyNote"
```

### Encoding Requirements

| Character | Encoded | Notes |
|-----------|---------|-------|
| Space | `%20` | Most critical |
| `/` | `%2F` | In file paths |
| `?` | `%3F` | Query delimiter |
| `#` | `%23` | Fragment identifier |
| `&` | `%26` | Parameter separator |
| `%` | `%25` | The percent sign itself |

**Linux caveat:** `xdg-open` requires double-encoding (space = `%2520`).

### Automation Patterns

**Quick capture to daily note (macOS shortcut):**

```bash
open --background "obsidian://adv-uri?vault=MyVault&daily=true&clipboard=true&mode=append&heading=Inbox"
```

**Batch frontmatter update:**

```bash
for file in "Note1" "Note2" "Note3"; do
    encoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${file}', safe=''))")
    open --background "obsidian://adv-uri?vault=MyVault&filepath=${encoded}&frontmatterkey=status&data=reviewed"
    sleep 0.5
done
```

**Search and replace in file:**

```bash
open "obsidian://adv-uri?vault=MyVault&filepath=Tasks&search=TODO&replace=DONE"
```

## Decision Points

### URI vs CLI (v1.12+)

| Factor | URI Protocol | CLI |
|--------|-------------|-----|
| Read file content | No (one-way) | Yes (`obsidian read`) |
| Return data | Limited (x-callback-url) | Full stdout, JSON |
| Cross-device (iOS/Android) | Yes | No (desktop only) |
| Tasks, tags, links | No native | Yes |
| Plugin management | Yes (Advanced URI) | Yes |
| Frontmatter | Yes (Advanced URI) | Yes |
| Sync controls | No | Yes |
| Developer tools | No | Yes |
| External app integration | Any app can open URL | Terminal/scripts only |
| Requires plugins | For advanced features | No |

**Use URIs when:** Mobile/iOS automation, cross-app integration (Shortcuts, Alfred, Raycast), external apps need to trigger Obsidian actions.

**Use CLI when:** Desktop automation, AI agent workflows, need return data, need search/graph queries.

**Use both when:** Desktop scripts that need cross-app communication (URI) plus data retrieval (CLI).

## References

- [Obsidian URI - Official Help](https://help.obsidian.md/Extending+Obsidian/Obsidian+URI)
- [Advanced URI Plugin](https://github.com/Vinzent03/obsidian-advanced-uri)
- [Advanced URI Docs](https://publish.obsidian.md/advanced-uri-doc/Home)
- [Actions URI Plugin](https://github.com/czottmann/obsidian-actions-uri)
- [Actions URI Docs](https://zottmann.dev/obsidian-actions-uri/)
- [Shell Commands Plugin](https://github.com/Taitava/obsidian-shellcommands)
- Obsidian vault note: `~/notes/reference/Obsidian URI Reference.md`
