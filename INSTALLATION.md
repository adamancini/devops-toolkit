# Installation Guide

## Marketplace Installation (Recommended)

This plugin is now distributed as a marketplace, which provides better version management and prevents cache invalidation issues.

### Method 1: Add Marketplace

```bash
# Add the marketplace
/plugin marketplace add adamancini/devops-toolkit

# Install the plugin
/plugin install devops-toolkit@adamancini-devops-toolkit

# Restart Claude Code
```

### Method 2: Direct GitHub URL

```bash
# Add marketplace via GitHub URL
/plugin marketplace add https://github.com/adamancini/devops-toolkit

# Install the plugin
/plugin install devops-toolkit@adamancini-devops-toolkit

# Restart Claude Code
```

## Verification

After installation and restart, verify the plugin is loaded:

```bash
# List installed plugins
/plugin list

# You should see:
# devops-toolkit@adamancini-devops-toolkit
```

## Usage

Once installed, all agents and skills are automatically available:

**Agents:**
- `obsidian-notes`
- `home-manager`
- `linear-assistant`
- `claudemd-compliance-checker`
- `helm-chart-developer`
- `mcp-security-validator`
- And more...

**Skills:**
- `ssl-cert-manager`
- `aerospace-config-manager`
- `linear-mcp-operations`
- `git-repo-organizer`
- `notion-sync`
- `replicated-cli`
- `system-updates`
- `yadm-utilities`
- `zsh-config-manager`

Simply use natural language to invoke them:
```
"Create a wildcard certificate for *.example.com"
"Configure aerospace for my workspace"
"Check Linear issue ANN-41"
```

## Updating

To update to the latest version:

```bash
# Update the marketplace
/plugin marketplace update adamancini-devops-toolkit

# Reinstall the plugin
/plugin install devops-toolkit@adamancini-devops-toolkit

# Restart Claude Code
```

## Uninstallation

```bash
# Uninstall the plugin
/plugin uninstall devops-toolkit@adamancini-devops-toolkit

# Optionally remove the marketplace
/plugin marketplace remove adamancini-devops-toolkit
```

## Troubleshooting

### Plugin not found after installation

1. Verify marketplace is added:
   ```bash
   /plugin marketplace list
   ```

2. Verify plugin is installed:
   ```bash
   /plugin list
   ```

3. Restart Claude Code (required after installation)

### Cache issues

The marketplace structure prevents cache invalidation issues. If you previously installed this as a direct plugin from `~/.claude/plugins/repos/`, remove that installation:

```bash
rm -rf ~/.claude/plugins/repos/devops-toolkit
```

### JSON validation errors

Verify the manifest files are valid:
```bash
python3 -m json.tool < .claude-plugin/plugin.json
python3 -m json.tool < .claude-plugin/marketplace.json
```

## Development

If you're developing this plugin locally:

1. Clone the repository:
   ```bash
   git clone https://github.com/adamancini/devops-toolkit ~/src/github.com/adamancini/devops-toolkit
   ```

2. Add as a local marketplace:
   ```bash
   /plugin marketplace add ~/src/github.com/adamancini/devops-toolkit
   /plugin install devops-toolkit@adamancini-devops-toolkit
   ```

3. Make changes and reinstall:
   ```bash
   /plugin uninstall devops-toolkit@adamancini-devops-toolkit
   /plugin install devops-toolkit@adamancini-devops-toolkit
   # Restart Claude Code
   ```

## Version History

See [CHANGELOG.md](./CHANGELOG.md) for version history and release notes.
