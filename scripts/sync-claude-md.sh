#!/usr/bin/env bash
#
# sync-claude-md.sh — Distribute master CLAUDE.md to workspace and service repos.
#
# Usage:
#   ./scripts/sync-claude-md.sh                  # sync to workspace root
#   ./scripts/sync-claude-md.sh --repos          # sync to workspace root + each service repo
#   WORKSPACE=/path/to/java ./scripts/sync-claude-md.sh  # custom workspace path
#
# Master source: goplay-devops/quality/claude/CLAUDE.md
# Target:        $WORKSPACE/CLAUDE.md (and optionally each service repo root)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MASTER="${DEVOPS_ROOT}/quality/claude/CLAUDE.md"

# Default workspace: parent of goplay-devops
WORKSPACE="${WORKSPACE:-$(cd "$DEVOPS_ROOT/.." && pwd)}"

# Service repos to sync (when --repos is specified)
SERVICE_REPOS=(
    goplay-api-service
    goplay-game-service
    goplay-back-service
    goplay-merchant-service
    goplay-push-service
    goplay-message-service
    goplay-task-service
    gp-payment-service
    goplay-bom
)

HEADER="<!-- AUTO-GENERATED: Do not edit. Master source: goplay-devops/quality/claude/CLAUDE.md -->"

if [[ ! -f "$MASTER" ]]; then
    echo "ERROR: Master CLAUDE.md not found at $MASTER" >&2
    exit 1
fi

sync_to() {
    local target="$1"
    local dir
    dir="$(dirname "$target")"

    if [[ ! -d "$dir" ]]; then
        echo "  SKIP $target (directory not found)"
        return
    fi

    # Write header + master content
    {
        echo "$HEADER"
        echo ""
        cat "$MASTER"
    } > "$target"

    echo "  OK   $target"
}

echo "Syncing CLAUDE.md from: $MASTER"
echo ""

# Always sync to workspace root
echo "[workspace]"
sync_to "${WORKSPACE}/CLAUDE.md"

# Optionally sync to each service repo
if [[ "${1:-}" == "--repos" ]]; then
    echo ""
    echo "[service repos]"
    for repo in "${SERVICE_REPOS[@]}"; do
        sync_to "${WORKSPACE}/${repo}/CLAUDE.md"
    done
fi

echo ""
echo "Done."
