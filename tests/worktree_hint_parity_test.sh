#!/usr/bin/env bash
# tests/worktree_hint_parity_test.sh
# Verifies that the worktree navigation hint block is identical across all sources.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# We need to check:
# 1. openchad: config/opencode/skills/worktree/SKILL.md
# 2. openchad: README.md
# 3. ADV: .opencode/command/adv-apply.md (if available)
# 4. ADV: ADV_INSTRUCTIONS.md (if available)

_passes=0
_fails=0

pass() { echo -e "\e[32m  PASS:\e[0m $1"; _passes=$((_passes + 1)); }
fail() { echo -e "\e[31m  FAIL:\e[0m $1"; _fails=$((_fails + 1)); }

echo "── Worktree Navigation Hint Parity ──"

# The canonical keybinds that must be present
REQUIRED_BINDS=("Ctrl+b n" "Ctrl+b l" "Ctrl+b w" "oc switch")

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
    for bind in "${REQUIRED_BINDS[@]}"; do
        if ! echo "$content" | grep -q "$bind"; then
            fail "$name is missing keybind: $bind"
            missing=1
        fi
    done
    
    if echo "$content" | grep -q "oc window"; then
        fail "$name contains deprecated 'oc window' command"
        missing=1
    fi
    
    if [ "$missing" -eq 0 ]; then
        pass "$name contains all canonical navigation keybinds"
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
