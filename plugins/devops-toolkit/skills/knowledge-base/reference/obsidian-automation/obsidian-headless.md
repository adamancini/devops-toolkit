---
topic: obsidian-automation
source: https://help.obsidian.md/headless
created: 2026-03-01
updated: 2026-03-01
tags:
  - obsidian
  - sync
  - headless
  - automation
  - ci-cd
---

# Obsidian Headless (Sync Client)

## Summary

Obsidian Headless is an official Node.js CLI client for Obsidian Sync that syncs vaults without the desktop app. Released February 27, 2026 as open beta (npm v0.0.3), it enables server-side vault sync for CI/CD, automated publishing, and AI agent access. It is sync-only -- it does not run plugins, the editor, or any vault intelligence. Requires Node.js 22+ and an active Obsidian Sync subscription.

## Key Concepts

### What It Is (and Isn't)

| Is | Is NOT |
|----|--------|
| CLI sync client for Obsidian Sync servers | A headless version of the Obsidian app |
| Bidirectional file synchronization | A plugin execution environment |
| Supports e2ee (AES-256-GCM, scrypt) | A search/query engine |
| Runs as a daemon or one-shot | The Obsidian CLI (separate tool, controls desktop app) |

### Architecture

- Connects to Obsidian Sync servers via WebSocket
- Downloads/uploads vault files to a local directory
- Preserves file creation timestamps (birthtime) on macOS/Windows via native N-API addon
- Linux: birthtime not supported (sync works without it)
- Continuous mode: watches filesystem + WebSocket for bidirectional real-time sync
- One-shot mode: single pull-push cycle, then exits

### Comparison: Headless vs Git-Based Sync

| Factor | Obsidian Headless | Git-based (current) |
|--------|-------------------|---------------------|
| Conflict resolution | Obsidian Sync's 3-way merge | Git merge (manual for binary) |
| Config sync | Selective (plugins, appearance, hotkeys) | Everything tracked in .obsidian/ |
| Cost | $4-10/month Sync subscription | Free |
| Device limit | 5 per vault | Unlimited |
| Encryption | e2ee available | At-rest only (GPG) |
| Server requirement | Node.js 22+ | Git |
| Plugin sync | Config only, not execution | Full .obsidian/ directory |
| Selective sync | No (full vault only) | Yes (gitignore) |
| Read-only mode | Not available | Yes (just don't push) |
| Offline support | Queue-based with reconnect | Full offline |

## Practical Application

### Installation

```bash
npm install -g obsidian-headless
```

### Authentication

```bash
# Interactive login
ob login [--email EMAIL] [--password PASSWORD] [--mfa CODE]

# Non-interactive (CI/scripts)
export OBSIDIAN_AUTH_TOKEN=<token>
```

### Command Reference

| Command | Description | Key Options |
|---------|-------------|-------------|
| `ob login` | Authenticate with Obsidian account | `--email`, `--password`, `--mfa` |
| `ob sync-list-remote` | List remote vaults (including shared) | |
| `ob sync-list-local` | List locally configured vaults | |
| `ob sync-create-remote` | Create new remote vault | `--name`, `--encryption <standard|e2ee>`, `--password`, `--region` |
| `ob sync-setup` | Connect local dir to remote vault | `--vault <id-or-name>`, `--path`, `--password`, `--device-name`, `--config-dir` |
| `ob sync-settings` | View/change sync settings | Config categories (see below) |
| `ob sync` | Run one-time sync | |
| `ob sync --continuous` | Run continuous sync (watch mode) | |
| `ob sync-disconnect` | Disconnect vault, remove credentials | |

### Sync Settings Categories

Configurable via `ob sync-settings` (comma-separated):

- `app` -- Core app settings
- `appearance` -- Theme and appearance settings
- `appearance-data` -- Themes and CSS snippets
- `hotkey` -- Keyboard shortcuts
- `core-plugin` -- Core plugin enabled/disabled state
- `core-plugin-data` -- Core plugin configuration data
- `community-plugin` -- Community plugin list
- `community-plugin-data` -- Community plugin settings

Set to empty string to disable config syncing entirely.

### Deployment Patterns

**Systemd service (continuous sync):**

```ini
[Unit]
Description=Obsidian Headless Sync
After=network.target

[Service]
ExecStart=/usr/local/bin/ob sync --continuous
Environment=OBSIDIAN_AUTH_TOKEN=<token>
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

**CI/CD pipeline (one-shot):**

```bash
export OBSIDIAN_AUTH_TOKEN=$SECRET_TOKEN
ob sync-setup --vault "My Vault" --path ./vault
ob sync
# Process vault files...
```

**Publishing pipeline:**

1. Headless sync pulls vault to server
2. Script processes synced files
3. Static site generator (Hugo/Quartz) builds site
4. Deploy to hosting

### Third-Party: vault-sync (MCP Bridge)

[vault-sync](https://github.com/alexjbarnes/vault-sync) wraps headless sync with an MCP server for AI assistants. Provides 8 tools (list, read, search, write, edit, delete, move, copy). Docker-deployable, Go 1.25+, OAuth 2.1 auth.

## Decision Points

**Use Obsidian Headless when:**
- You have an Obsidian Sync subscription
- Need server-side vault access for automation
- Want e2ee in transit
- Building automated publishing pipelines
- Giving AI agents vault access on a server

**Keep git-based sync when:**
- No Sync subscription (cost-sensitive)
- Need selective sync (specific folders only)
- Need read-only server access
- Need unlimited device connections
- Need full offline capability with manual merge control

**Consider vault-sync (MCP) when:**
- AI assistants need vault access without filesystem exposure
- Want OAuth-protected vault operations
- Need structured API over raw file access

## Known Limitations

1. **Sync-only**: No plugin execution, no search, no graph queries
2. **No selective sync**: Full vault or nothing
3. **No read-only mode**: Always bidirectional
4. **Device slots**: Consumes 1 of 5 allowed devices
5. **No webhooks**: No programmatic change notification
6. **Linux keychain bug**: `ob sync-setup` fails without desktop secrets service -- use `OBSIDIAN_AUTH_TOKEN` workaround
7. **Very early**: v0.0.3 open beta, days old as of March 2026
8. **Server security**: With e2ee vaults, decrypted files exist on server filesystem

## References

- [Obsidian Headless Help](https://help.obsidian.md/headless)
- [Headless Sync Docs](https://help.obsidian.md/sync/headless)
- [GitHub: obsidianmd/obsidian-headless](https://github.com/obsidianmd/obsidian-headless)
- [npm: obsidian-headless](https://www.npmjs.com/package/obsidian-headless)
- [vault-sync MCP Bridge](https://github.com/alexjbarnes/vault-sync)
- [Blogging with Obsidian Headless](https://utf9k.net/blog/obsidian-headless/)
- [WebProNews Analysis](https://www.webpronews.com/obsidians-headless-sync-how-a-note-taking-app-is-quietly-building-infrastructure-for-developers-and-power-users/)
- Obsidian vault note: `~/notes/reference/Obsidian Headless Reference.md`
