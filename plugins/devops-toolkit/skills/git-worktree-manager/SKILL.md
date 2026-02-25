---
name: git-worktree-manager
description: Use when creating git worktrees for parallel development, setting up isolated workspaces for Claude Code agents, navigating between worktrees, or cleaning up worktrees after branches are merged. Covers the `gwt` shell function and `.worktrees/` directory convention.
---

# Git Worktree Manager

Manage git worktrees using the `gwt` shell function and the `.worktrees/` directory convention. Worktrees enable parallel development on multiple branches from a single repository without stashing or switching branches.

## Directory Convention

Worktrees live inside the repository root under `.worktrees/`:

```
~/src/github.com/org/repo/          # main branch (bare checkout)
├── .worktrees/                     # all worktrees live here
│   ├── feat-new-api/               # feature branch worktree
│   ├── bug-fix-auth/               # bugfix branch worktree
│   └── refactor-db-layer/          # refactor branch worktree
├── .gitignore                      # contains .worktrees entry
├── src/
└── ...
```

This layout keeps worktrees colocated with the repo for easy discovery and navigation. The `.worktrees/` directory is automatically added to `.gitignore` by `gwt`.

## The `gwt` Shell Function

Defined in `~/.zshrcd/conf.d/git-worktree.zsh` and auto-sourced by zsh.

### Create a Worktree

```bash
cd ~/src/github.com/org/repo    # navigate to repo root
gwt feat-new-api                # creates .worktrees/feat-new-api
```

Behavior:
- If the branch exists locally, checks it out as a worktree
- If the branch exists on `origin`, creates a tracking branch
- If the branch is new, creates it from current HEAD
- Ensures `.worktrees` is listed in `.gitignore`

### List Worktrees

```bash
gwt -l
```

### Remove a Worktree

```bash
gwt -d feat-new-api
```

Prompts whether to also delete the branch after removing the worktree.

### Help

```bash
gwt -h
```

## Working in Worktrees

### Navigate to a Worktree

```bash
cd .worktrees/feat-new-api
# or with tab completion:
cd .worktrees/feat-<TAB>
```

### Invoke Claude Code in a Worktree

```bash
cd .worktrees/feat-new-api
claude                          # starts Claude Code scoped to this worktree
```

Claude Code inherits the worktree's working directory and branch context. Each worktree is a fully independent working directory with its own staged/unstaged changes.

### Open in VS Code

```bash
code .worktrees/feat-new-api
```

### Run Commands in a Worktree

```bash
# From repo root, target a worktree directly
make -C .worktrees/feat-new-api test
git -C .worktrees/feat-new-api status
```

## Agent Worktree Isolation

When Claude Code agents use `isolation: "worktree"`, they create temporary worktrees via the internal Task tool mechanism. The `gwt` function serves a different purpose: **user-initiated, persistent worktrees** for parallel development sessions.

### When to Use `gwt` vs Agent Worktrees

| Scenario | Use `gwt` | Use agent `isolation: "worktree"` |
|----------|-----------|----------------------------------|
| User wants to work on a feature branch | Yes | No |
| Agent needs temporary isolation for a task | No | Yes |
| User wants to run Claude in a branch | Yes | No |
| Agent making speculative changes | No | Yes |
| Long-lived parallel development | Yes | No |

### Recommending `gwt` to Users

When a user asks to "work on a feature branch", "start a new branch", or "set up parallel development", suggest using `gwt`:

```bash
# From the repo root
gwt feat-branch-name
cd .worktrees/feat-branch-name
claude   # or: code .
```

## Worktree Lifecycle

### Standard Workflow

1. **Create**: `gwt feat-new-api` from repo root
2. **Develop**: `cd .worktrees/feat-new-api` and work normally
3. **Commit**: Standard git operations work within the worktree
4. **Push**: `git push -u origin feat-new-api`
5. **Merge**: Merge via PR or locally from main
6. **Clean up**: `gwt -d feat-new-api`

### After Merging a Branch

```bash
# From repo root
gwt -d feat-new-api    # removes worktree, prompts to delete branch
```

### Listing Active Work

```bash
gwt -l                 # shows all worktrees with their branches and paths
```

## Gitignore Handling

`gwt` automatically ensures `.worktrees` is in the repo's `.gitignore`. If the line is missing, it appends it. This prevents worktree directories from being committed to the repository.

If `.gitignore` doesn't exist, `gwt` creates it with `.worktrees` as the first entry.

## Quick Reference

| Task | Command |
|------|---------|
| Create worktree | `gwt <branch-name>` |
| List worktrees | `gwt -l` |
| Remove worktree | `gwt -d <branch-name>` |
| Navigate to worktree | `cd .worktrees/<branch-name>` |
| Run Claude in worktree | `cd .worktrees/<branch> && claude` |
| Open in VS Code | `code .worktrees/<branch-name>` |

## Cross-References

- **git-repo-organizer skill** -- repository placement conventions (worktrees inherit the parent repo's location)
- **zsh-config-manager skill** -- the `gwt` function lives in `~/.zshrcd/conf.d/git-worktree.zsh`
- **yadm-utilities skill** -- track the `gwt` function with yadm
