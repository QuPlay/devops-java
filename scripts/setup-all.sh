#!/bin/bash
# ==============================================================================
# DevOps Git Hooks - Setup All Repositories
#
# Scans sibling directories for git repositories and installs hooks in each.
# Run this after cloning goplay-devops.
#
# Usage:
#   cd goplay-devops/scripts && ./setup-all.sh
#   or: bash goplay-devops/scripts/setup-all.sh
#
# Compatible: macOS, Linux, Windows (Git Bash / MSYS2)
# ==============================================================================
set -e

# Colors (safe for Git Bash on Windows)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Locate script directory and workspace root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVOPS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$DEVOPS_ROOT/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   DevOps Git Hooks - Setup All Repositories    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Workspace:${NC} $WORKSPACE_ROOT"
echo ""

# Counters
TOTAL=0
INSTALLED=0
SKIPPED=0
FAILED=0

# Find all sibling git repositories
for dir in "$WORKSPACE_ROOT"/*/; do
    # Skip non-directories and devops itself
    [ ! -d "$dir" ] && continue
    dirname=$(basename "$dir")

    # Skip devops repo
    if [ "$dirname" = "goplay-devops" ] || [ "$dirname" = "devops-java" ] || [ "$dirname" = "DevOps-Java" ]; then
        continue
    fi

    # Must be a git repository
    if [ ! -d "$dir/.git" ]; then
        continue
    fi

    TOTAL=$((TOTAL + 1))
    echo -n "  Setting up ${dirname}... "

    # Run setup-hooks.sh in the repo
    cd "$dir"
    if bash "$SCRIPT_DIR/setup-hooks.sh" > /tmp/setup-hooks-output-$$ 2>&1; then
        INSTALLED=$((INSTALLED + 1))
        echo -e "${GREEN}OK${NC}"
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
            SKIPPED=$((SKIPPED + 1))
            echo -e "${YELLOW}SKIPPED${NC}"
        else
            FAILED=$((FAILED + 1))
            echo -e "${RED}FAILED${NC}"
            # Show last few lines of output for debugging
            tail -3 /tmp/setup-hooks-output-$$ 2>/dev/null | sed 's/^/    /'
        fi
    fi
    rm -f /tmp/setup-hooks-output-$$
    cd "$WORKSPACE_ROOT"
done

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "  Total repositories:  ${TOTAL}"
echo -e "  Installed/Updated:   ${GREEN}${INSTALLED}${NC}"
[ $SKIPPED -gt 0 ] && echo -e "  Skipped:             ${YELLOW}${SKIPPED}${NC}"
[ $FAILED -gt 0 ] && echo -e "  Failed:              ${RED}${FAILED}${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Some repositories failed. Run setup-hooks.sh manually in those repos.${NC}"
    exit 1
fi
