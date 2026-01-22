#!/bin/bash
#
# sync-replicated-elements.sh
#
# Synchronizes Replicated-related agents, commands, and skills from
# replicatedhq/dot-claude to this devops-toolkit plugin.
#
# Usage:
#   ./scripts/sync-replicated-elements.sh [--local PATH] [--commit] [--dry-run]
#
# Options:
#   --local PATH   Use existing local clone of replicatedhq/dot-claude
#   --commit       Automatically commit changes after sync
#   --dry-run      Show what would be done without making changes
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and plugin root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
LOCAL_PATH=""
AUTO_COMMIT=false
DRY_RUN=false
TEMP_DIR=""
SOURCE_REPO="https://github.com/replicatedhq/dot-claude.git"

# Replicated-specific files that need repl- prefix
REPL_AGENTS=(
    "proposal-needed"
    "proposal-writer"
    "proposals-analyzer"
    "proposals-locator"
    "researcher"
    "testing"
    "shortcut"
)

# Generic agents (no prefix, reusable across projects)
GENERIC_AGENTS=(
    "codebase-analyzer"
    "codebase-locator"
    "codebase-pattern-finder"
    "web-search-researcher"
)

# Commands to sync
REPL_COMMANDS=(
    "proposal"
)

# Logging functions (output to stderr to avoid mixing with function returns)
log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[OK]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Cleanup function
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --local)
                LOCAL_PATH="$2"
                shift 2
                ;;
            --commit)
                AUTO_COMMIT=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Synchronize Replicated-related elements from replicatedhq/dot-claude.

Options:
  --local PATH   Use existing local clone instead of fetching fresh
  --commit       Automatically commit changes after sync
  --dry-run      Show what would be done without making changes
  -h, --help     Show this help message

Examples:
  # Sync from fresh clone
  $(basename "$0")

  # Sync from local path
  $(basename "$0") --local ~/src/github.com/replicatedhq/dot-claude

  # Sync and auto-commit
  $(basename "$0") --commit

  # Preview changes without applying
  $(basename "$0") --dry-run
EOF
}

# Get source directory (clone or use local)
get_source_dir() {
    if [[ -n "$LOCAL_PATH" ]]; then
        if [[ ! -d "$LOCAL_PATH" ]]; then
            log_error "Local path does not exist: $LOCAL_PATH"
            exit 1
        fi
        log_info "Using local path: $LOCAL_PATH"

        # Pull latest if it's a git repo
        if [[ -d "$LOCAL_PATH/.git" ]]; then
            log_info "Pulling latest changes..."
            if ! $DRY_RUN; then
                (cd "$LOCAL_PATH" && git pull --quiet) || log_warn "Could not pull latest changes"
            fi
        fi

        echo "$LOCAL_PATH"
    else
        TEMP_DIR=$(mktemp -d)
        log_info "Cloning $SOURCE_REPO to temporary directory..."
        # Always clone even in dry-run to show accurate diff
        git clone --quiet --depth 1 "$SOURCE_REPO" "$TEMP_DIR"
        echo "$TEMP_DIR"
    fi
}

# Update internal references in a file to use repl- prefix
update_references() {
    local file="$1"

    if $DRY_RUN; then
        log_info "Would update references in: $file"
        return
    fi

    # Update agent name in frontmatter
    local basename_file
    basename_file=$(basename "$file" .md)
    if [[ "$basename_file" == repl-* ]]; then
        local original_name="${basename_file#repl-}"
        sed -i '' "s/^name: ${original_name}$/name: ${basename_file}/" "$file"
    fi

    # Update references to other agents
    # proposal-writer references
    sed -i '' 's/`researcher`/`repl-researcher`/g' "$file"
    sed -i '' 's/`testing`/`repl-testing`/g' "$file"
    sed -i '' 's/\*\*researcher\*\*/\*\*repl-researcher\*\*/g' "$file"
    sed -i '' 's/\*\*testing\*\*/\*\*repl-testing\*\*/g' "$file"

    # researcher references
    sed -i '' 's/\*\*proposals-locator\*\*/\*\*repl-proposals-locator\*\*/g' "$file"
    sed -i '' 's/\*\*proposals-analyzer\*\*/\*\*repl-proposals-analyzer\*\*/g' "$file"
    sed -i '' 's/\*\*shortcut\*\*/\*\*repl-shortcut\*\*/g' "$file"

    # command references
    sed -i '' 's/^- proposal-needed$/- repl-proposal-needed/' "$file"
    sed -i '' 's/^- proposal-writer$/- repl-proposal-writer/' "$file"
    sed -i '' 's/use the shortcut agent/use the repl-shortcut agent/g' "$file"

    # Update description to mention Replicated
    if [[ "$basename_file" == repl-* ]]; then
        # Add "Replicated" to descriptions where appropriate
        sed -i '' 's/when you need to produce a new proposal$/when you need to produce a new proposal for Replicated work/' "$file"
        sed -i '' 's/when you need to decide if a proposal should be written for a change\./when you need to decide if a proposal should be written for a Replicated change./' "$file"
        sed -i '' 's/when you need to conduct research into the existing codebase/when you need to conduct research into the existing Replicated codebase/' "$file"
        sed -i '' 's/when designing a plan to write tests\./when designing a plan to write tests for Replicated projects./' "$file"
    fi
}

# Sync agents
sync_agents() {
    local source_dir="$1"
    local dest_dir="$PLUGIN_ROOT/agents"

    log_info "Syncing agents..."

    # Sync Replicated-specific agents with repl- prefix
    for agent in "${REPL_AGENTS[@]}"; do
        local src="$source_dir/agents/${agent}.md"
        local dst="$dest_dir/repl-${agent}.md"

        if [[ -f "$src" ]]; then
            if $DRY_RUN; then
                log_info "Would copy: $src -> $dst"
            else
                cp "$src" "$dst"
                update_references "$dst"
                log_success "Synced: repl-${agent}.md"
            fi
        else
            log_warn "Source not found: $src"
        fi
    done

    # Sync generic agents without prefix
    for agent in "${GENERIC_AGENTS[@]}"; do
        local src="$source_dir/agents/${agent}.md"
        local dst="$dest_dir/${agent}.md"

        if [[ -f "$src" ]]; then
            if $DRY_RUN; then
                log_info "Would copy: $src -> $dst"
            else
                cp "$src" "$dst"
                log_success "Synced: ${agent}.md"
            fi
        else
            log_warn "Source not found: $src"
        fi
    done
}

# Sync commands
sync_commands() {
    local source_dir="$1"
    local dest_dir="$PLUGIN_ROOT/commands"

    log_info "Syncing commands..."

    # Ensure commands directory exists
    mkdir -p "$dest_dir"

    for cmd in "${REPL_COMMANDS[@]}"; do
        local src="$source_dir/commands/${cmd}.md"
        local dst="$dest_dir/repl-${cmd}.md"

        if [[ -f "$src" ]]; then
            if $DRY_RUN; then
                log_info "Would copy: $src -> $dst"
            else
                cp "$src" "$dst"
                update_references "$dst"
                log_success "Synced: repl-${cmd}.md"
            fi
        else
            log_warn "Source not found: $src"
        fi
    done
}

# Show summary of changes
show_summary() {
    log_info "Summary of synced elements:"
    echo "" >&2
    echo "Replicated-specific agents (repl- prefix):" >&2
    for agent in "${REPL_AGENTS[@]}"; do
        echo "  - repl-${agent}" >&2
    done
    echo "" >&2
    echo "Generic agents (no prefix):" >&2
    for agent in "${GENERIC_AGENTS[@]}"; do
        echo "  - ${agent}" >&2
    done
    echo "" >&2
    echo "Commands:" >&2
    for cmd in "${REPL_COMMANDS[@]}"; do
        echo "  - /repl-${cmd}" >&2
    done
}

# Commit changes
commit_changes() {
    if ! $AUTO_COMMIT; then
        return
    fi

    log_info "Committing changes..."

    if $DRY_RUN; then
        log_info "Would commit changes"
        return
    fi

    cd "$PLUGIN_ROOT"

    # Check if there are changes to commit
    if git diff --quiet && git diff --cached --quiet; then
        log_info "No changes to commit"
        return
    fi

    # Stage all agent and command files
    git add agents/*.md commands/*.md 2>/dev/null || true

    # Get source commit info if available
    local source_info=""
    if [[ -n "$LOCAL_PATH" && -d "$LOCAL_PATH/.git" ]]; then
        source_info=" from $(cd "$LOCAL_PATH" && git rev-parse --short HEAD)"
    fi

    git commit -m "$(cat <<EOF
Sync Replicated elements from replicatedhq/dot-claude${source_info}

Updated agents and commands from upstream source.
EOF
)"

    log_success "Changes committed"
}

# Main
main() {
    parse_args "$@"

    log_info "Starting Replicated elements sync..."
    echo "" >&2

    if $DRY_RUN; then
        log_warn "DRY RUN MODE - No changes will be made"
        echo "" >&2
    fi

    local source_dir
    source_dir=$(get_source_dir)

    # Verify source has expected structure
    if [[ ! -d "$source_dir/agents" ]]; then
        log_error "Source directory does not have expected structure (missing agents/)"
        exit 1
    fi

    sync_agents "$source_dir"
    sync_commands "$source_dir"

    echo "" >&2
    show_summary

    echo "" >&2
    commit_changes

    echo "" >&2
    log_success "Sync complete!"

    if ! $AUTO_COMMIT && ! $DRY_RUN; then
        echo "" >&2
        log_info "Review changes with: git diff"
        log_info "Commit with: git add -A && git commit -m 'Sync Replicated elements'"
    fi
}

main "$@"
