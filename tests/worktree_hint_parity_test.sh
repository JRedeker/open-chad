#!/usr/bin/env bash
# tests/worktree_hint_parity_test.sh
# Verifies that worktree inline mode documentation is consistent across all sources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

_passes=0
_fails=0

pass() { echo -e "\e[32m  PASS:\e[0m $1"; _passes=$((_passes + 1)); }
fail() { echo -e "\e[31m  FAIL:\e[0m $1"; _fails=$((_fails + 1)); }

echo "── Worktree Inline Mode Documentation Parity ──"

# The canonical phrases that must be present in inline mode docs
REQUIRED_PHRASES=("inline" "workdir")

# Phrases that should NOT appear in the default worktree flow
DEPRECATED_PHRASES=("Ctrl+b n" "Ctrl+b l" "oc window")

check_file() {
    local file="$1"
    local name="$2"

    if [ ! -f "$file" ]; then
        echo "  SKIP: $name not found"
        return
    fi

    local content
    content=$(cat "$file")

    local missing=0
    for phrase in "${REQUIRED_PHRASES[@]}"; do
        if ! echo "$content" | grep -qi "$phrase"; then
            fail "$name is missing required phrase: $phrase"
            missing=1
        fi
    done

    for phrase in "${DEPRECATED_PHRASES[@]}"; do
        if echo "$content" | grep -q "$phrase"; then
            fail "$name contains deprecated phrase: $phrase"
            missing=1
        fi
    done

    if [ "$missing" -eq 0 ]; then
        pass "$name has correct inline mode documentation"
    fi
}

check_file "$REPO_DIR/config/opencode/skills/worktree/SKILL.md" "worktree/SKILL.md"
check_file "$REPO_DIR/README.md" "README.md"

# Check ADV repo if it exists alongside openchad
ADV_DIR="$REPO_DIR/../oc-plugins/advance"
if [ -d "$ADV_DIR" ]; then
    # Only check ADV files if the repo is on trunk (installer tests may pin it to older SHAs)
    _adv_branch=$(git -C "$ADV_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
    if [ "$_adv_branch" = "trunk" ]; then
        check_file "$ADV_DIR/.opencode/command/adv-apply.md" "adv-apply.md"
        check_file "$ADV_DIR/ADV_INSTRUCTIONS.md" "ADV_INSTRUCTIONS.md"
    else
        echo "  SKIP: ADV repo is not on trunk (branch: $_adv_branch) — skipping parity check"
    fi
fi

echo ""
echo "════════════════════════════════════"
echo "  Results: $_passes passed, $_fails failed"
echo "════════════════════════════════════"

exit "$_fails"
