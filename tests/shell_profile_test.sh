#!/usr/bin/env bash
# tests/shell_profile_test.sh — Test suite for lib/setup_shell_profile.sh
#
# Tests: shell detection, idempotent PATH writes, fallback to .profile,
#        reload command output, marker-comment guard
#
# Usage: bash tests/shell_profile_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_DIR/lib/setup_shell_profile.sh"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq() {
    if [ "$1" = "$2" ]; then
        pass "$3"
    else
        fail "$3 (expected='$2' got='$1')"
    fi
}

assert_contains() {
    if grep -qF "$2" "$1" 2>/dev/null; then
        pass "$3"
    else
        fail "$3 (pattern '$2' not found in $1)"
    fi
}

assert_not_contains() {
    if ! grep -qF "$2" "$1" 2>/dev/null; then
        pass "$3"
    else
        fail "$3 (pattern '$2' unexpectedly found in $1)"
    fi
}

assert_count() {
    local actual
    actual=$(grep -cF "$2" "$1" 2>/dev/null | head -1 | tr -d '[:space:]')
    actual="${actual:-0}"
    if [ "$actual" -eq "$3" ]; then
        pass "$4"
    else
        fail "$4 (expected count=$3, got=$actual in $1)"
    fi
}

assert_file_exists() {
    if [ -f "$1" ]; then
        pass "file exists: $1"
    else
        fail "file missing: $1"
    fi
}

assert_executable() {
    if [ -x "$1" ]; then
        pass "executable: $1"
    else
        fail "not executable: $1"
    fi
}

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment Setup ───────────────────────────────────────────────────

setup_tmp_home() {
    TMP_DIR=$(mktemp -d)
    TMP_HOME="$TMP_DIR/home"
    mkdir -p "$TMP_HOME"
    export HOME="$TMP_HOME"
}

teardown_tmp_home() {
    rm -rf "$TMP_DIR"
    unset TMP_DIR TMP_HOME
}

# ─── Section 0: Script existence ─────────────────────────────────────────────

section "Script existence"

assert_file_exists "$HELPER"
assert_executable "$HELPER"

# ─── Section 1: bash detection → writes to .bashrc ───────────────────────────

section "bash detection writes to .bashrc"

setup_tmp_home
touch "$TMP_HOME/.bashrc"

SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1

assert_file_exists "$TMP_HOME/.bashrc" "bash: .bashrc exists after run"
assert_contains "$TMP_HOME/.bashrc" "BEGIN open-chad" "bash: BEGIN marker written to .bashrc"
assert_contains "$TMP_HOME/.bashrc" "END open-chad" "bash: END marker written to .bashrc"
assert_contains "$TMP_HOME/.bashrc" '.local/bin' "bash: .local/bin PATH export in .bashrc"
assert_not_contains "$TMP_HOME/.zshrc" "BEGIN open-chad" "bash: .zshrc not written when bash detected" 2>/dev/null || true

teardown_tmp_home

# ─── Section 2: zsh detection → writes to .zshrc ─────────────────────────────

section "zsh detection writes to .zshrc"

setup_tmp_home
touch "$TMP_HOME/.zshrc"

SHELL=/bin/zsh bash "$HELPER" >/dev/null 2>&1

assert_file_exists "$TMP_HOME/.zshrc" "zsh: .zshrc exists after run"
assert_contains "$TMP_HOME/.zshrc" "BEGIN open-chad" "zsh: BEGIN marker written to .zshrc"
assert_contains "$TMP_HOME/.zshrc" "END open-chad" "zsh: END marker written to .zshrc"
assert_contains "$TMP_HOME/.zshrc" '.local/bin' "zsh: .local/bin PATH export in .zshrc"
assert_not_contains "$TMP_HOME/.bashrc" "BEGIN open-chad" "zsh: .bashrc not written when zsh detected" 2>/dev/null || true

teardown_tmp_home

# ─── Section 3: Idempotency — no duplicate block on re-run ───────────────────

section "Idempotency: no duplicate block on re-run"

setup_tmp_home
touch "$TMP_HOME/.bashrc"

# Run twice
SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1
SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1

assert_count "$TMP_HOME/.bashrc" "BEGIN open-chad" 1 "bash: BEGIN marker appears exactly once after 2 runs"
assert_count "$TMP_HOME/.bashrc" "END open-chad" 1 "bash: END marker appears exactly once after 2 runs"
assert_count "$TMP_HOME/.bashrc" ".local/bin" 1 "bash: .local/bin export appears exactly once after 2 runs"

teardown_tmp_home

# ─── Section 4: zsh idempotency ───────────────────────────────────────────────

section "Idempotency: zsh no duplicate block on re-run"

setup_tmp_home
touch "$TMP_HOME/.zshrc"

SHELL=/bin/zsh bash "$HELPER" >/dev/null 2>&1
SHELL=/bin/zsh bash "$HELPER" >/dev/null 2>&1

assert_count "$TMP_HOME/.zshrc" "BEGIN open-chad" 1 "zsh: BEGIN marker appears exactly once after 2 runs"
assert_count "$TMP_HOME/.zshrc" "END open-chad" 1 "zsh: END marker appears exactly once after 2 runs"

teardown_tmp_home

# ─── Section 5: Fallback to .profile when neither .bashrc nor .zshrc exist ───

section "Fallback to .profile when no rc file exists"

setup_tmp_home
# No .bashrc, no .zshrc — only .profile exists
touch "$TMP_HOME/.profile"

SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1

assert_contains "$TMP_HOME/.profile" "BEGIN open-chad" "fallback: BEGIN marker written to .profile"
assert_contains "$TMP_HOME/.profile" '.local/bin' "fallback: .local/bin export in .profile"

teardown_tmp_home

# ─── Section 6: Fallback creates .profile if nothing exists ──────────────────

section "Fallback creates .profile if no rc files exist at all"

setup_tmp_home
# No rc files at all

SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1

assert_file_exists "$TMP_HOME/.profile" "fallback: .profile created when no rc files exist"
assert_contains "$TMP_HOME/.profile" "BEGIN open-chad" "fallback: BEGIN marker in created .profile"

teardown_tmp_home

# ─── Section 7: Reload command output ────────────────────────────────────────

section "Reload command output matches detected shell"

setup_tmp_home
touch "$TMP_HOME/.bashrc"

bash_output=$(SHELL=/bin/bash bash "$HELPER" 2>&1)
if echo "$bash_output" | grep -q "source.*\.bashrc"; then
    pass "bash: reload command mentions source ~/.bashrc"
else
    fail "bash: reload command does not mention source ~/.bashrc (output: $bash_output)"
fi

teardown_tmp_home

setup_tmp_home
touch "$TMP_HOME/.zshrc"

zsh_output=$(SHELL=/bin/zsh bash "$HELPER" 2>&1)
if echo "$zsh_output" | grep -q "source.*\.zshrc"; then
    pass "zsh: reload command mentions source ~/.zshrc"
else
    fail "zsh: reload command does not mention source ~/.zshrc (output: $zsh_output)"
fi

teardown_tmp_home

# ─── Section 8: Existing content is preserved ────────────────────────────────

section "Existing .bashrc content is preserved"

setup_tmp_home
echo "# my existing config" > "$TMP_HOME/.bashrc"
echo "alias ll='ls -la'" >> "$TMP_HOME/.bashrc"

SHELL=/bin/bash bash "$HELPER" >/dev/null 2>&1

assert_contains "$TMP_HOME/.bashrc" "my existing config" "bash: pre-existing content preserved"
assert_contains "$TMP_HOME/.bashrc" "alias ll='ls -la'" "bash: pre-existing alias preserved"
assert_contains "$TMP_HOME/.bashrc" "BEGIN open-chad" "bash: new block appended after existing content"

teardown_tmp_home

# ─── Section 9: Unknown shell falls back gracefully ──────────────────────────

section "Unknown shell falls back to .profile"

setup_tmp_home
touch "$TMP_HOME/.profile"

SHELL=/usr/bin/fish bash "$HELPER" >/dev/null 2>&1

assert_contains "$TMP_HOME/.profile" "BEGIN open-chad" "unknown shell: falls back to .profile"

teardown_tmp_home

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────"
echo "Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "────────────────────────────────────────────────────"

exit "$TESTS_FAILED"
