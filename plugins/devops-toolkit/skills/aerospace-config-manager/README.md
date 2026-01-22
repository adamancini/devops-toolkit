# AeroSpace Configuration Manager

Safe and comprehensive management of AeroSpace window manager configurations on macOS with automatic backup, validation, and rollback.

## Features

### Safe Configuration Management

- **Automatic backup** before every change
- **TOML validation** (syntax and semantic)
- **Preview changes** with colored diffs
- **Easy rollback** to any previous state
- **Metadata tracking** (timestamps, descriptions, validation status)

### Application Management

- **Auto-discovery** of macOS bundle IDs
- **Workspace assignments** for applications
- **Floating vs tiling** window rules
- **Smart defaults** for common applications

### Keybinding Management

- **Conflict detection** across:
  - AeroSpace internal conflicts
  - macOS system shortcuts
  - Application-specific bindings
- **Intelligent suggestions** following user patterns
- **Multi-mode support** (main mode, service mode)

### Multi-Monitor Support

- Workspace distribution strategies
- Monitor focus keybindings
- Dynamic workspace assignment

### Documentation Generation

- Markdown cheatsheets
- Current keybinding exports
- Visual reference cards

## Quick Start

### Assign Application to Workspace

```
User: "Assign Google Chrome to workspace 2"
```

The skill will:
1. Discover bundle ID (`com.google.Chrome`)
2. Check for existing assignments
3. Preview TOML changes
4. Create backup
5. Apply configuration
6. Reload AeroSpace

### Add Keybinding

```
User: "Add keybinding for fullscreen toggle"
```

The skill will:
1. Suggest key (e.g., `alt-m`)
2. Check conflicts (AeroSpace, macOS, apps)
3. Show alternatives if conflicts found
4. Preview addition
5. Backup config
6. Apply and reload

### Make Application Float

```
User: "Make 1Password always float"
```

The skill will:
1. Discover bundle ID
2. Check smart defaults (password managers should float)
3. Preview TOML
4. Apply change
5. Prompt to restart app

## Prerequisites

- **AeroSpace**: [Install AeroSpace](https://github.com/nikitabobko/AeroSpace)
- **Python 3.11+**: For TOML validation
- **macOS 14+**: For latest features

```bash
# Install AeroSpace (if not already installed)
brew install --cask nikitabobko/tap/aerospace

# Verify Python version
python3 --version  # Should be 3.11+
```

## Configuration

No additional configuration required. Works with existing `~/.aerospace.toml`.

### Backup Location

Backups stored in: `~/.aerospace.toml.backups/`

```bash
# View backups
ls -lt ~/.aerospace.toml.backups/ | head -10

# Each backup includes:
# - aerospace.toml.YYYYMMDD-HHMMSS (config file)
# - metadata.YYYYMMDD-HHMMSS.json (change description)
```

## Usage Examples

### Workspace Layout Setup

```
User: "Set up my development workspace layout"
```

Interactive wizard:
1. Detects running applications
2. Suggests workspace assignments:
   - Workspace 1: Browser (Firefox, Chrome)
   - Workspace 2: Editor (Cursor, VSCode)
   - Workspace 3: Terminal (Ghostty, iTerm)
   - Workspace 4: Documentation (Obsidian, Notes)
   - Workspace 5: Communication (Slack, Zoom)
3. Allows customization
4. Creates backup
5. Applies configuration
6. Generates cheatsheet

### Fix Keybinding Conflict

```
User: "My alt+h keybinding isn't working"
```

Diagnostic mode:
1. Checks binding in config
2. Tests for conflicts:
   - AeroSpace: ✓ No conflicts
   - macOS: ⚠️  Terminal may capture
   - Apps: ⚠️  Help menu shortcut
3. Suggests alternatives:
   - `alt-left` (arrow key, more universal)
   - `ctrl-h` (less likely to conflict)
4. User selects alternative
5. Applies change safely

### Multi-Monitor Configuration

```
User: "Configure aerospace for my dual monitor setup"
```

The skill will:
1. Detect monitors via `aerospace list-monitors`
2. Present distribution strategies:
   - Split workspaces (1-5 → Monitor 1, 6-9 → Monitor 2)
   - Dynamic assignment
   - Per-app monitor assignment
3. Configure workspace-to-monitor mapping
4. Add monitor focus keybindings
5. Apply and test

### Generate Cheatsheet

```
User: "Show me my aerospace keybindings"
```

Generates markdown cheatsheet:
- Grouped by category (navigation, workspaces, layouts)
- Current keybindings from config
- Mode-specific bindings
- Workspace assignments
- Floating window rules

## Common Bundle IDs

```
Browsers:
  Firefox: org.mozilla.firefox
  Chrome: com.google.Chrome
  Safari: com.apple.Safari
  Arc: company.thebrowser.Browser

Editors:
  Cursor: com.todesktop.230313mzl4w4u92
  VSCode: com.microsoft.VSCode
  IntelliJ: com.jetbrains.intellij

Terminals:
  Ghostty: com.mitchellh.ghostty
  iTerm2: com.googlecode.iterm2
  Kitty: net.kovidgoyal.kitty

Communication:
  Slack: com.tinyspeck.slackmacgap
  Zoom: us.zoom.xos
  Discord: com.hnc.Discord

Productivity:
  Obsidian: md.obsidian
  Notion: notion.id
  Notes: com.apple.Notes
  Finder: com.apple.finder
```

Find more:
```bash
# List running apps with bundle IDs
aerospace list-apps

# Get bundle ID for specific app
osascript -e 'id of app "Application Name"'
```

## Troubleshooting

### Keybinding Not Working

**Diagnostic steps:**
1. Check if AeroSpace is running:
   ```bash
   ps aux | grep -i aerospace
   ```
2. Verify binding exists in config:
   ```bash
   grep "alt-j" ~/.aerospace.toml
   ```
3. Test if macOS is capturing the key
4. Check for application-specific overrides
5. Reload config:
   ```bash
   aerospace reload-config
   ```

### App Not Moving to Workspace

**Common causes:**
- Incorrect bundle ID
- App needs to be restarted (assignments only work on window creation)
- TOML syntax error

**Solution:**
```bash
# Verify bundle ID
aerospace list-apps | grep -i "App Name"

# Validate TOML
python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"

# Restart the application
```

### Configuration Reload Failed

**Error**: AeroSpace won't reload config

**Solution:**
```bash
# Check AeroSpace logs
log show --predicate 'process == "AeroSpace"' --last 5m

# Validate TOML syntax
python3 -c "
import tomllib
with open('$HOME/.aerospace.toml', 'rb') as f:
    try:
        config = tomllib.load(f)
        print('✓ Valid TOML')
    except tomllib.TOMLDecodeError as e:
        print(f'✗ TOML Error: {e}')
"

# If errors, rollback to last good backup
```

### TOML Syntax Errors

**Common mistakes:**

1. **Missing commas in arrays:**
```toml
# Wrong
run= [
  "move-node-to-workspace 1"
  "layout tiling"
]

# Correct
run= [
  "move-node-to-workspace 1",
  "layout tiling",
]
```

2. **Incorrect quoting:**
```toml
# Wrong
alt-enter = "exec-and-forget open -a "Ghostty""

# Correct
alt-enter = '''exec-and-forget open -a "Ghostty"'''
```

3. **Duplicate keys:**
```toml
# Wrong - second overrides first
alt-j = 'focus left'
alt-j = 'focus down'

# Correct - use different keys
alt-j = 'focus left'
alt-k = 'focus down'
```

## Backup and Rollback

### List Backups

```bash
ls -lt ~/.aerospace.toml.backups/ | grep "\.toml\." | head -10
```

### Restore Backup

```
User: "Rollback my aerospace config to yesterday"
```

The skill will:
1. List available backups with descriptions
2. Show diff between current and selected backup
3. Confirm restoration
4. Backup current config (safety)
5. Restore selected backup
6. Reload AeroSpace
7. Verify success

### Manual Rollback

```bash
# Backup current config first
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$TIMESTAMP

# Restore specific backup
BACKUP_TIMESTAMP="20251119-143022"
cp ~/.aerospace.toml.backups/aerospace.toml.$BACKUP_TIMESTAMP ~/.aerospace.toml

# Reload config
aerospace reload-config
```

## Integration

### YADM Dotfile Management

If `~/.aerospace.toml` is tracked by YADM:

```bash
# Skill will detect and offer to commit
yadm status
yadm add ~/.aerospace.toml
yadm commit -m "aerospace: Added Chrome to workspace 2"
```

### Git Integration

If in a git repository:

```bash
# Show diff
git diff ~/.aerospace.toml

# Commit changes
git add ~/.aerospace.toml
git commit -m "aerospace: Configure multi-monitor setup"
```

### Task Runner Integration

Add AeroSpace tasks to `Taskfile.yml`:

```yaml
version: '3'

tasks:
  aerospace:backup:
    desc: Backup AeroSpace configuration
    cmds:
      - mkdir -p ~/.aerospace.toml.backups
      - cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$(date +%Y%m%d-%H%M%S)

  aerospace:reload:
    desc: Reload AeroSpace configuration
    cmds:
      - aerospace reload-config

  aerospace:validate:
    desc: Validate TOML configuration
    cmds:
      - python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"
```

## Best Practices

1. **Always backup first**: Never skip the backup step
2. **Preview before applying**: Review TOML changes
3. **Validate everything**: TOML syntax + semantic checks
4. **Test after changes**: Confirm new features work
5. **Follow patterns**: Use same modifier and navigation style
6. **Document changes**: Save descriptions in metadata
7. **Easy rollback**: Keep at least 10 recent backups

## Advanced Configuration

### Workspace-to-Monitor Assignment

```toml
[workspace-to-monitor-force-assignment]
1 = 'main'
2 = 'main'
3 = 'main'
6 = 'secondary'
7 = 'secondary'
```

### Service Mode Keybindings

```toml
[mode.service.binding]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
f = ['layout floating tiling', 'mode main']
```

### On-Window-Detected Rules

```toml
[[on-window-detected]]
if.app-id="com.google.Chrome"
run= [
  "move-node-to-workspace 2",
  "layout tiling",
]
```

## Available AeroSpace Commands

**Navigation:**
- `focus left|down|up|right`
- `focus-monitor left|right`
- `move left|down|up|right`

**Workspaces:**
- `workspace N` (1-9)
- `workspace-back-and-forth`
- `move-node-to-workspace N`

**Layouts:**
- `layout tiles horizontal|vertical`
- `layout accordion horizontal|vertical`
- `layout floating|tiling`

**Windows:**
- `close`
- `fullscreen on|off|toggle`
- `join-with left|down|up|right`

**System:**
- `reload-config`
- `mode <mode-name>`
- `exec-and-forget <command>`

## Security

- All configuration changes are backed up locally
- No remote access or data transmission
- Backups stored in `~/.aerospace.toml.backups/`
- TOML validation prevents syntax errors
- Easy rollback if issues occur

## Support

For issues or questions:
- Check [main plugin README](../../README.md)
- Review [troubleshooting section](#troubleshooting) above
- Open issue on [GitHub](https://github.com/adamancini/devops-toolkit/issues)

## Resources

- [AeroSpace Documentation](https://nikitabobko.github.io/AeroSpace/)
- [AeroSpace GitHub](https://github.com/nikitabobko/AeroSpace)
- [TOML Specification](https://toml.io/)
