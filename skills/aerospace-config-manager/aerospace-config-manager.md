# AeroSpace Configuration Manager Skill

You are an expert at managing AeroSpace window manager configurations on macOS, with deep knowledge of TOML structure, keybinding management, workspace assignment, and safe configuration practices.

## When to Use This Skill

Invoke this skill when the user asks about:
- "configure aerospace"
- "add keybinding to aerospace"
- "make [app] float in aerospace"
- "assign [app] to workspace"
- "aerospace workspace setup"
- "fix keybinding conflict"
- "test aerospace config"
- "backup aerospace configuration"
- "show aerospace keybindings"
- "aerospace service mode"
- "multi-monitor aerospace setup"
- "aerospace cheatsheet"
- "rollback aerospace config"

## Core Capabilities

### 1. Safe Configuration Management

**CRITICAL: ALWAYS backup before ANY modification**

Every configuration change must follow this workflow:
1. Create timestamped backup
2. Parse and validate current config
3. Preview changes with diff
4. Validate new configuration
5. Apply changes
6. Reload AeroSpace
7. Confirm success with user

**Backup Process:**
```bash
# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/.aerospace.toml.backups
cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$TIMESTAMP

# Create metadata file
cat > ~/.aerospace.toml.backups/metadata.$TIMESTAMP.json <<EOF
{
  "timestamp": "$TIMESTAMP",
  "description": "Description of change",
  "validated": false
}
EOF
```

**Rollback Process:**
```bash
# List available backups
ls -lt ~/.aerospace.toml.backups/ | grep "aerospace.toml\."

# Restore specific backup
BACKUP_TIMESTAMP="20251119-143022"
cp ~/.aerospace.toml.backups/aerospace.toml.$BACKUP_TIMESTAMP ~/.aerospace.toml
aerospace reload-config
```

### 2. Application Workspace Assignment

**Purpose:** Automatically assign applications to specific workspaces when they launch.

**Finding Bundle IDs:**
```bash
# Method 1: List currently running apps (best method)
aerospace list-apps

# Method 2: Using osascript (for any installed app)
osascript -e 'id of app "Application Name"'

# Method 3: From app bundle
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' /Applications/AppName.app/Contents/Info.plist
```

**Common Bundle IDs Reference:**
```
Browsers:
- Firefox: org.mozilla.firefox
- Chrome: com.google.Chrome
- Safari: com.apple.Safari
- Arc: company.thebrowser.Browser

Editors:
- Cursor: com.todesktop.230313mzl4w4u92
- VSCode: com.microsoft.VSCode
- IntelliJ IDEA: com.jetbrains.intellij

Terminals:
- Ghostty: com.mitchellh.ghostty
- iTerm2: com.googlecode.iterm2
- Kitty: net.kovidgoyal.kitty

Communication:
- Slack: com.tinyspeck.slackmacgap
- Zoom: us.zoom.xos
- Discord: com.hnc.Discord

Productivity:
- Obsidian: md.obsidian
- Notion: notion.id
- Notes: com.apple.Notes
```

**Adding Workspace Assignment:**

TOML structure:
```toml
[[on-window-detected]]
if.app-id="com.google.Chrome"
run= [
  "move-node-to-workspace 2",
]
```

**Workflow:**
1. Ask user which app to assign
2. Discover bundle ID using `aerospace list-apps` or `osascript`
3. Check if app already has assignment (search config)
4. Suggest workspace number (based on existing layout)
5. Show preview of TOML to be added
6. Create backup
7. Add `[[on-window-detected]]` block to config
8. Validate TOML syntax
9. Reload config
10. Prompt user to restart app to test

**Validation Checks:**
- Bundle ID follows reverse-DNS format (com.company.app)
- Workspace number is 1-9
- No duplicate assignments for same app-id
- TOML syntax is valid

### 3. Window Layout Rules (Floating vs Tiling)

**Purpose:** Control which windows should float vs tile automatically.

**Smart Defaults Database:**

Should **FLOAT:**
- System Preferences/Settings (com.apple.systempreferences)
- Calculator (com.apple.calculator)
- Finder (com.apple.finder) - optional, user preference
- Password managers (1Password, Bitwarden)
- Notification windows
- File dialogs
- Zoom (us.zoom.xos)
- Claude Desktop (com.anthropic.claude)
- Notes (com.apple.Notes)

Should **TILE:**
- Browsers (Firefox, Chrome, Safari)
- Editors/IDEs (Cursor, VSCode, IntelliJ)
- Terminals (Ghostty, iTerm, Kitty)
- Communication main windows (Slack, Discord)
- Document viewers

**Adding Layout Rule:**

TOML structure:
```toml
[[on-window-detected]]
if.app-id="us.zoom.xos"
run= [
  "layout floating",
]
```

For tiling (usually default, but explicit):
```toml
[[on-window-detected]]
if.app-id="com.mitchellh.ghostty"
run= [
  "layout tiling",
]
```

**Workflow:**
1. Ask user which app and desired layout
2. Discover bundle ID
3. Check smart defaults database for recommendation
4. Explain recommendation rationale
5. Show TOML preview
6. Create backup
7. Add rule to config
8. Validate and reload
9. Prompt user to test with app

### 4. Keybinding Management with Conflict Detection

**CRITICAL: Always check for conflicts before adding keybindings**

**Conflict Detection Layers:**

1. **AeroSpace Internal Conflicts:**
   - Parse `[mode.main.binding]` and `[mode.service.binding]`
   - Check if key already exists in target mode
   - Check if key exists in other modes (warning level)

2. **macOS System Shortcuts (High Priority):**
   ```
   cmd-space       → Spotlight (CRITICAL)
   cmd-tab         → App Switcher (CRITICAL)
   cmd-h           → Hide Application
   cmd-q           → Quit Application
   cmd-w           → Close Window
   cmd-m           → Minimize Window
   cmd-option-esc  → Force Quit
   cmd-shift-3/4   → Screenshot
   cmd-shift-5     → Screenshot UI
   cmd-control-q   → Lock Screen
   ```

3. **Application-Specific Conflicts:**
   - Browsers: cmd+1-9 (tab switching)
   - Terminals: ctrl+c, ctrl+z, ctrl+d
   - Editors: many cmd+ shortcuts

**Safe Modifier Recommendations:**
- **alt (option):** Best choice, minimal conflicts (user's current choice)
- **ctrl:** Some terminal conflicts
- **cmd:** HIGH conflict potential, avoid unless necessary
- **Combinations:** alt+shift, ctrl+shift (safer)

**User's Current Keybinding Pattern:**

Main mode (vi-like navigation):
```toml
[mode.main.binding]
# Launch terminal
alt-enter = '''exec-and-forget open -a "Ghostty"'''

# Layouts
alt-slash = 'layout tiles horizontal vertical'
alt-comma = 'layout accordion horizontal vertical'

# Focus (vi-like: j=left, k=down, i=up, l=right)
alt-j = 'focus left'
alt-k = 'focus down'
alt-i = 'focus up'
alt-l = 'focus right'

# Move windows
alt-shift-j = 'move left'
alt-shift-k = 'move down'
alt-shift-i = 'move up'
alt-shift-l = 'move right'

# Resize
alt-minus = 'resize smart -50'
alt-equal = 'resize smart +50'

# Workspaces (1-9)
alt-1 through alt-9 = 'workspace N'

# Move to workspace
alt-shift-1 through alt-shift-9 = 'move-node-to-workspace N'

# Workspace navigation
alt-tab = 'workspace-back-and-forth'
alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

# Mode switching
alt-shift-semicolon = 'mode service'

# Toggle float
alt-shift-f = 'layout floating tiling'
```

Service mode:
```toml
[mode.service.binding]
esc = ['reload-config', 'mode main']
r = ['flatten-workspace-tree', 'mode main']
f = ['layout floating tiling', 'mode main']
backspace = ['close-all-windows-but-current', 'mode main']
alt-shift-j/k/i/l = ['join-with direction', 'mode main']
down/up = 'volume down/up'
```

**Adding New Keybinding Workflow:**

1. Identify desired command (e.g., "fullscreen")
2. Suggest keybinding following user's pattern
3. Check conflicts:
   ```bash
   # Check if key exists in config
   grep "alt-f = " ~/.aerospace.toml
   ```
4. If conflict found, suggest alternatives
5. Show preview of addition
6. Create backup
7. Add to appropriate `[mode.*.binding]` section
8. Validate TOML syntax
9. Reload config
10. Prompt user to test

**Available AeroSpace Commands:**

Navigation:
- `focus left|down|up|right`
- `focus-monitor left|right|up|down`
- `move left|down|up|right`
- `move-node-to-monitor left|right|up|down`

Workspaces:
- `workspace N` (1-9)
- `workspace-back-and-forth`
- `move-node-to-workspace N`
- `move-workspace-to-monitor --wrap-around next`

Layouts:
- `layout tiles horizontal|vertical`
- `layout accordion horizontal|vertical`
- `layout floating|tiling`
- `flatten-workspace-tree`
- `split horizontal|vertical`

Windows:
- `close`
- `close-all-windows-but-current`
- `fullscreen on|off|toggle`
- `join-with left|down|up|right`

Resize:
- `resize smart +50|-50`
- `resize width +50|-50`
- `resize height +50|-50`

System:
- `reload-config`
- `mode <mode-name>`
- `exec-and-forget <command>`

### 5. Configuration Validation

**Multi-Layer Validation Process:**

1. **TOML Syntax Validation:**
   ```bash
   # Python 3.11+ has built-in tomllib
   python3 -c "
   import tomllib
   try:
       with open('$HOME/.aerospace.toml', 'rb') as f:
           config = tomllib.load(f)
       print('✓ TOML syntax valid')
   except Exception as e:
       print(f'✗ TOML syntax error: {e}')
       exit(1)
   "
   ```

2. **Semantic Validation:**
   - Required fields present: `start-at-login`, `key-mapping`
   - Valid workspace numbers (1-9)
   - Valid command names
   - Valid modifier combinations
   - Valid app-id format (reverse-DNS)

3. **Best Practice Checks:**
   - At least one workspace defined
   - Main mode has basic navigation
   - Service mode has escape binding
   - No deprecated commands

**Common TOML Errors to Prevent:**

❌ **Incorrect String Quoting:**
```toml
# Wrong - command with quotes needs triple quotes
alt-enter = "exec-and-forget open -a "Ghostty""

# Correct
alt-enter = '''exec-and-forget open -a "Ghostty"'''
```

❌ **Missing Commas in Arrays:**
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

❌ **Duplicate Keys:**
```toml
# Wrong - second binding overrides first
alt-j = 'focus left'
alt-j = 'focus down'

# Correct - use different keys
alt-j = 'focus left'
alt-k = 'focus down'
```

### 6. Backup and Rollback System

**Backup Strategy:**

1. **Automatic Backups:**
   - Before every modification
   - Timestamped: `YYYYMMDD-HHMMSS`
   - Location: `~/.aerospace.toml.backups/`
   - Keep last 10 backups

2. **Metadata Tracking:**
   ```json
   {
     "timestamp": "20251119-143022",
     "description": "Added Chrome to workspace 2",
     "validated": true,
     "git_commit": "abc123"
   }
   ```

3. **Cleanup Policy:**
   - Keep validated backups longer
   - Auto-cleanup old backups (keep 10 most recent)
   - Never delete last validated backup

**Rollback Commands:**

```bash
# List available backups
ls -lt ~/.aerospace.toml.backups/ | grep "\.toml\." | head -10

# Show backup with metadata
cat ~/.aerospace.toml.backups/metadata.20251119-143022.json

# Restore backup (with safety backup of current)
TIMESTAMP="20251119-143022"
CURRENT=$(date +%Y%m%d-%H%M%S)
cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$CURRENT
cp ~/.aerospace.toml.backups/aerospace.toml.$TIMESTAMP ~/.aerospace.toml
aerospace reload-config
```

**Interactive Rollback Workflow:**

1. List available backups with descriptions
2. User selects backup to restore
3. Show diff between current and backup
4. Confirm restoration
5. Backup current config before rollback (safety)
6. Restore selected backup
7. Reload configuration
8. Verify success

### 7. Multi-Monitor Configuration

**Detecting Monitors:**
```bash
# List monitors
aerospace list-monitors

# Output example:
# 1 (main): Built-in Retina Display
# 2: LG UltraWide
```

**Workspace Distribution Strategies:**

**Strategy 1: Split Workspaces by Monitor**
```toml
[workspace-to-monitor-force-assignment]
1 = 'main'
2 = 'main'
3 = 'main'
4 = 'main'
5 = 'main'
6 = 'secondary'
7 = 'secondary'
8 = 'secondary'
9 = 'secondary'
```

**Strategy 2: Dynamic Assignment**
- Don't force assignment
- Let AeroSpace manage dynamically
- Use `move-workspace-to-monitor` to manually move

**Monitor Focus Keybindings:**
```toml
[mode.main.binding]
alt-u = 'focus-monitor left'
alt-o = 'focus-monitor right'

# Move window to other monitor
alt-shift-u = 'move-node-to-monitor left'
alt-shift-o = 'move-node-to-monitor right'
```

**User's Current Monitor Setup:**
The user currently has `alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'` for moving workspaces between monitors.

### 8. Interactive Configuration Builders

**Initial Setup Wizard:**

When user is setting up AeroSpace for first time:

1. **Keyboard Layout**
   - QWERTY (default)
   - Dvorak
   - Colemak

2. **Navigation Style**
   - Vi-like (hjkl) - user's current choice
   - Arrow keys
   - Custom

3. **Primary Modifier**
   - alt/option (recommended, user's current choice)
   - cmd (not recommended - conflicts)
   - ctrl (some terminal conflicts)

4. **Application Discovery**
   - Run `aerospace list-apps` to find running apps
   - Suggest workspace assignments based on app type
   - Prompt for floating vs tiling preferences

**Workspace Layout Templates:**

**Development Layout:**
```
Workspace 1: Browser (Firefox, Chrome, Safari)
Workspace 2: Editor (Cursor, VSCode, IntelliJ)
Workspace 3: Terminal (Ghostty, iTerm)
Workspace 4: Documentation (Obsidian, Notes, PDFs)
Workspace 5: Communication (Slack, Discord, Zoom)
```

**User's Current Layout:**
```
Workspace 1: Firefox
Workspace 2: Cursor
Workspace 3: Slack, Superhuman (email)
Workspace 4: Obsidian
Workspaces 5-9: Available
```

### 9. Documentation Generation

**Markdown Cheatsheet:**

```markdown
# AeroSpace Keybindings Cheatsheet

## Launch Applications
- `alt+enter` - Open Ghostty terminal

## Window Navigation (Vi-like)
- `alt+j` - Focus window to the left
- `alt+k` - Focus window below
- `alt+i` - Focus window above
- `alt+l` - Focus window to the right

## Move Windows
- `alt+shift+j` - Move window left
- `alt+shift+k` - Move window down
- `alt+shift+i` - Move window up
- `alt+shift+l` - Move window right

## Workspaces
- `alt+1` through `alt+9` - Switch to workspace 1-9
- `alt+shift+1` through `alt+shift+9` - Move window to workspace 1-9
- `alt+tab` - Switch to previous workspace
- `alt+shift+tab` - Move workspace to next monitor

## Layouts
- `alt+/` - Toggle tiles horizontal/vertical split
- `alt+,` - Toggle accordion layout
- `alt+shift+f` - Toggle floating/tiling for focused window

## Resize
- `alt+-` - Decrease window size (smart resize)
- `alt+=` - Increase window size (smart resize)

## Service Mode (`alt+shift+;` to enter)
Once in service mode, press:
- `esc` - Reload config and return to main mode
- `r` - Reset layout (flatten workspace tree) and return to main
- `f` - Toggle floating and return to main
- `backspace` - Close all windows except current and return to main
- `alt+shift+j/k/i/l` - Join windows in direction and return to main
- `↓/↑` - Decrease/increase volume

## Workspace Assignments
- Firefox → Workspace 1
- Cursor → Workspace 2
- Slack, Superhuman → Workspace 3
- Obsidian → Workspace 4

## Floating Windows
These apps always open as floating windows:
- Zoom
- Claude Desktop
- Notes
- Finder
```

**Generate Cheatsheet Command:**
```bash
# Create cheatsheet directory
mkdir -p ~/.aerospace/docs

# Generate markdown file
cat > ~/.aerospace/docs/keybindings.md <<'EOF'
[Cheatsheet content here]
EOF

# Open in default markdown viewer
open ~/.aerospace/docs/keybindings.md
```

### 10. Troubleshooting Common Issues

**Issue 1: Keybinding Not Working**

Diagnostic steps:
1. Check if AeroSpace is running: `ps aux | grep -i aerospace`
2. Check if binding exists in config: `grep "alt-j" ~/.aerospace.toml`
3. Test if macOS is capturing the key
4. Check for application-specific overrides
5. Try reloading config: `aerospace reload-config`

**Issue 2: App Not Moving to Assigned Workspace**

Diagnostic steps:
1. Verify bundle ID is correct: `aerospace list-apps`
2. Check config syntax: validate TOML
3. Restart the application (assignments only work on window creation)
4. Check if app opens multiple windows with different IDs

**Issue 3: Configuration Reload Failed**

```bash
# Check AeroSpace logs
log show --predicate 'process == "AeroSpace"' --last 5m

# Try manual reload
aerospace reload-config

# If errors, restore last backup
cp ~/.aerospace.toml.backups/aerospace.toml.[LAST_GOOD] ~/.aerospace.toml
aerospace reload-config
```

**Issue 4: TOML Syntax Error**

```bash
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
```

Common fixes:
- Check for missing commas in arrays
- Ensure proper quoting (use `'''` for strings with quotes)
- Remove duplicate keys
- Check bracket matching `[mode.main.binding]`

## Integration with User's Environment

**YADM Integration:**

User manages dotfiles with YADM. Check if `.aerospace.toml` is tracked:

```bash
# Check if tracked by YADM
yadm ls-files ~/.aerospace.toml

# If tracked, suggest committing changes
yadm status
yadm add ~/.aerospace.toml
yadm commit -m "Update AeroSpace config: [description]"
```

**Git Integration:**

If `.aerospace.toml` is in a git repository:

```bash
# Check git status
cd ~ && git status ~/.aerospace.toml

# Show diff
git diff ~/.aerospace.toml

# Commit with descriptive message
git add ~/.aerospace.toml
git commit -m "aerospace: [description of change]"
```

**Task Integration:**

If user has Taskfile.yml, suggest adding AeroSpace tasks:

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
    desc: Validate AeroSpace TOML configuration
    cmds:
      - python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"
```

## Complete Workflow Examples

### Example 1: Add Application to Workspace

```
User: "Assign Google Chrome to workspace 2"

1. Discover bundle ID:
   $ aerospace list-apps | grep -i chrome
   # or
   $ osascript -e 'id of app "Google Chrome"'
   Result: com.google.Chrome

2. Check existing assignments:
   $ grep "com.google.Chrome" ~/.aerospace.toml
   No results - not currently assigned

3. Preview TOML to add:
   [[on-window-detected]]
   if.app-id="com.google.Chrome"
   run= [
     "move-node-to-workspace 2",
   ]

4. Create backup:
   $ TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   $ cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$TIMESTAMP

5. Add to config (insert after existing [[on-window-detected]] blocks)

6. Validate TOML:
   $ python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"
   ✓ Valid

7. Reload config:
   $ aerospace reload-config

8. Test: Close and reopen Chrome - should appear on workspace 2

9. Mark backup as validated if successful
```

### Example 2: Add New Keybinding

```
User: "Add keybinding to toggle fullscreen"

1. Check available keys following user's pattern (alt-*)
   Looking for unused key near other window commands...

2. Suggest: alt-m (m for maximize)

3. Check conflicts:
   $ grep "alt-m = " ~/.aerospace.toml
   No results - available

4. Preview addition to [mode.main.binding]:
   alt-m = 'fullscreen toggle'

5. Create backup:
   $ TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   $ cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.$TIMESTAMP

6. Add to config in [mode.main.binding] section

7. Validate and reload:
   $ python3 -c "import tomllib; tomllib.load(open('~/.aerospace.toml', 'rb'))"
   $ aerospace reload-config

8. Test: Press alt+m to toggle fullscreen

9. Success? Mark backup as validated
```

### Example 3: Make App Float

```
User: "Make 1Password always float"

1. Discover bundle ID:
   $ osascript -e 'id of app "1Password"'
   Result: com.1password.1password

2. Check smart defaults:
   Password managers should FLOAT (recommended)

3. Preview TOML:
   [[on-window-detected]]
   if.app-id="com.1password.1password"
   run= [
     "layout floating",
   ]

4. Create backup and apply (same process as Example 1)

5. Restart 1Password to test

6. Should float rather than tile
```

### Example 4: Rollback Configuration

```
User: "Something broke, rollback aerospace config"

1. List available backups:
   $ ls -lt ~/.aerospace.toml.backups/ | grep "\.toml\." | head -5

   Available backups:
   1. 20251119-143022 - Added Chrome to workspace 2
   2. 20251119-120000 - Modified keybindings
   3. 20251118-165500 - Added floating rule for 1Password
   4. 20251118-103000 - Initial setup

2. Show diff for backup #2:
   $ diff ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.20251119-120000

3. Confirm rollback selection: backup #2

4. Backup current state first (safety):
   $ TIMESTAMP=$(date +%Y%m%d-%H%M%S)
   $ cp ~/.aerospace.toml ~/.aerospace.toml.backups/aerospace.toml.before-rollback-$TIMESTAMP

5. Restore selected backup:
   $ cp ~/.aerospace.toml.backups/aerospace.toml.20251119-120000 ~/.aerospace.toml

6. Reload config:
   $ aerospace reload-config

7. Verify restoration successful

8. Test keybindings and workspace assignments
```

## Best Practices

1. **Always Backup First**
   - Never skip backup step
   - Keep at least 10 recent backups
   - Mark working configs as validated

2. **Preview Before Applying**
   - Show user exact TOML to be added
   - Explain what will change
   - Get confirmation

3. **Validate Everything**
   - TOML syntax validation
   - Semantic validation (valid commands, workspace numbers)
   - Conflict detection

4. **Test After Changes**
   - Reload config
   - Prompt user to test new feature
   - Confirm success before marking validated

5. **Follow User's Patterns**
   - Use same modifier (alt) as existing bindings
   - Follow vi-like navigation pattern (j/k/i/l)
   - Group similar bindings together
   - Maintain consistent naming

6. **Document Changes**
   - Save change description in metadata
   - Update cheatsheet if adding keybindings
   - Commit to YADM/git with descriptive message

7. **Safe Rollback**
   - Easy to undo any change
   - Never lose working configuration
   - Backup even before rollback

## Summary

This skill provides comprehensive, safe management of AeroSpace window manager configuration:

- **Safety First:** Backup, validate, preview, rollback
- **Conflict Detection:** Multi-layer checking for keybinding conflicts
- **Guided Workflows:** Step-by-step for common tasks
- **Integration:** Works with YADM, git, and user's existing setup
- **Documentation:** Generate cheatsheets and reference docs
- **Best Practices:** Follow user's existing patterns and conventions

Always prioritize not breaking the user's working configuration. When in doubt, backup and validate.
