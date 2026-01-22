---
name: zsh-config-manager
description: Use when adding shell configuration for a new tool, creating zsh component files, configuring shell completions, using yadm alternates for OS-specific shell config, or troubleshooting modular zsh setup in conf.d structure.
---

# Zsh Configuration Manager

Manage modular zsh configuration in the `~/.zshrcd/` directory structure with automatic sourcing, yadm tracking, and OS-specific alternates.

## Configuration Structure

```
~/.zshrcd/
├── .zshrc              # Main config - loads conf.d/*.zsh
├── .zprofile           # Login shell profile
├── conf.d/             # Component files (auto-sourced)
│   ├── aliases.zsh
│   ├── docker.zsh
│   ├── homebrew.zsh##os.Darwin
│   └── kubectl-completion.zsh
├── completions/        # Custom completion functions
└── antigenrc           # Antigen plugin configuration
```

## Adding New Tool Configuration

### 1. Create Component File

```bash
# ~/.zshrcd/conf.d/tool-name.zsh

# Environment setup
export TOOL_HOME="$HOME/.tool"
path+=("$TOOL_HOME/bin")

# Aliases
alias tool='tool-command'

# Completions (guard with command check)
if command -v tool >/dev/null 2>&1; then
    source <(tool completion zsh)
fi
```

### 2. Track with Yadm

```bash
yadm add ~/.zshrcd/conf.d/tool-name.zsh
yadm commit -m "Add tool-name zsh configuration"
yadm push
```

## OS-Specific Configuration (Alternates)

For configurations that differ by OS:

```bash
# Create OS-specific versions
~/.zshrcd/conf.d/homebrew.zsh##os.Darwin    # macOS
~/.zshrcd/conf.d/homebrew.zsh##os.Linux     # Linux

# YADM creates symlink automatically:
# ~/.zshrcd/conf.d/homebrew.zsh → homebrew.zsh##os.Darwin
```

Environment or class-specific:

```bash
~/.zshrcd/.zprofile.local##class.Work
~/.zshrcd/.zprofile.local##class.Personal
```

## Quick Reference

| Task | Command |
|------|---------|
| Add new tool config | Create `~/.zshrcd/conf.d/tool.zsh` |
| Test without restart | `source ~/.zshrcd/conf.d/tool.zsh` |
| Full reload | `exec zsh` |
| Track new config | `yadm add ~/.zshrcd/conf.d/tool.zsh` |
| List components | `ls ~/.zshrcd/conf.d/` |

## Best Practices

**One component per file** - Easier to maintain, can enable/disable by removing file

**Guard commands:**
```bash
if command -v kubectl >/dev/null 2>&1; then
    # kubectl-specific config
fi
```

**Meaningful names:**
- `docker.zsh` not `docker-config.zsh`
- `kubectl-completion.zsh` not `k8s-stuff.zsh`

**Never source directly in .zshrc** - The auto-sourcing loop handles it:
```bash
# In .zshrc (already configured)
for file in $ZDOTDIR/conf.d/*.zsh; do
    source $file
done
```

## Common Mistakes

| Problem | Fix |
|---------|-----|
| Config not loading | Check file ends in `.zsh` |
| Slow shell startup | Add command guards to skip missing tools |
| Alternates not working | Run `yadm alt` to update symlinks |
| Changes not synced | Remember `yadm add/commit/push` |
