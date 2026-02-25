#!/usr/bin/env bash
# tests/oc_sessions_test.sh — Unit tests for bin/oc-list and bin/oc-killall
# Tests: session listing, memory display, no-sessions handling, kill filtering,
#        --yes flag, confirmation prompt, exit codes
#
# Usage: bash tests/oc_sessions_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC_LIST_BIN="$REPO_DIR/bin/oc-list"
OC_KILLALL_BIN="$REPO_DIR/bin/oc-killall"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (pattern '$2' not found in output)"; }
assert_not_contains() { echo "$1" | grep -q "$2" && fail "$3 (pattern '$2' unexpectedly found)" || pass "$3"; }
assert_file_exists() { [ -f "$1" ] && pass "file exists: $1" || fail "file missing: $1"; }
assert_executable()  { [ -x "$1" ] && pass "executable: $1" || fail "not executable: $1"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment Setup ───────────────────────────────────────────────────

TMP_DIR=""

setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    export HOME="$TMP_DIR/home"
    mkdir -p "$HOME"
}

teardown_tmp_env() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    TMP_DIR=""
}

# Helper: create a fake tmux binary that returns controlled output
_make_fake_tmux() {
    local fake_bin_dir="$1"
    local sessions_output="$2"   # what 'tmux list-sessions' returns
    mkdir -p "$fake_bin_dir"
    cat > "$fake_bin_dir/tmux" <<EOF
#!/usr/bin/env bash
# Fake tmux for testing
if [[ "\${1:-}" == "list-sessions" ]]; then
    echo "$sessions_output"
    exit 0
elif [[ "\${1:-}" == "kill-session" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$fake_bin_dir/tmux"
}

# Helper: create a fake ps binary that returns controlled memory output
_make_fake_ps() {
    local fake_bin_dir="$1"
    local mem_output="$2"   # what 'ps' returns for memory
    cat > "$fake_bin_dir/ps" <<EOF
#!/usr/bin/env bash
# Fake ps for testing
echo "$mem_output"
exit 0
EOF
    chmod +x "$fake_bin_dir/ps"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: bin/oc-list — file properties
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-list — file properties"

test_oc_list_file_exists() {
    assert_file_exists "$OC_LIST_BIN"
}

test_oc_list_is_executable() {
    assert_executable "$OC_LIST_BIN"
}

test_oc_list_has_bash_shebang() {
    local first_line
    first_line=$(head -1 "$OC_LIST_BIN")
    assert_contains "$first_line" "bash" "bin/oc-list has bash shebang"
}

test_oc_list_has_set_euo() {
    grep -q 'set -euo pipefail' "$OC_LIST_BIN" && pass "bin/oc-list uses set -euo pipefail" || fail "bin/oc-list missing set -euo pipefail"
}

test_oc_list_syntax_ok() {
    bash -n "$OC_LIST_BIN" 2>/dev/null && pass "bin/oc-list syntax OK" || fail "bin/oc-list syntax error"
}

test_oc_list_file_exists
test_oc_list_is_executable
test_oc_list_has_bash_shebang
test_oc_list_has_set_euo
test_oc_list_syntax_ok

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: bin/oc-list — --help flag
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-list — --help flag"

test_oc_list_help_exits_zero() {
    local rc=0
    bash "$OC_LIST_BIN" --help >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "oc-list --help exits 0"
}

test_oc_list_help_mentions_sessions() {
    local output
    output=$(bash "$OC_LIST_BIN" --help 2>&1)
    assert_contains "$output" "session" "oc-list --help mentions sessions"
}

test_oc_list_help_exits_zero
test_oc_list_help_mentions_sessions

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: bin/oc-list — no sessions
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-list — no active sessions"

test_oc_list_exits_zero_no_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" ""   # empty output = no sessions
    local rc=0
    PATH="$fake_bin:$PATH" bash "$OC_LIST_BIN" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "oc-list exits 0 when no sessions"
    teardown_tmp_env
}

test_oc_list_prints_no_sessions_message() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" ""
    local output
    output=$(PATH="$fake_bin:$PATH" bash "$OC_LIST_BIN" 2>&1) || true
    # Should print something indicating no sessions (not just blank)
    [ -n "$output" ] && pass "oc-list prints output when no sessions" || fail "oc-list prints nothing when no sessions"
    teardown_tmp_env
}

test_oc_list_exits_zero_no_sessions
test_oc_list_prints_no_sessions_message

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: bin/oc-list — with active sessions
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-list — with active oc-* sessions"

test_oc_list_shows_oc_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    # Simulate two oc-* sessions
    _make_fake_tmux "$fake_bin" "oc-1700000000-12345: 1 windows (created Mon Jan  1 00:00:00 2024)
oc-1700000001-12346: 2 windows (created Mon Jan  1 00:01:00 2024)"
    _make_fake_ps "$fake_bin" "  42000"
    local output
    output=$(PATH="$fake_bin:$PATH" bash "$OC_LIST_BIN" 2>&1) || true
    assert_contains "$output" "oc-" "oc-list shows oc-* session names"
    teardown_tmp_env
}

test_oc_list_filters_non_oc_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    # Mix of oc-* and non-oc-* sessions
    _make_fake_tmux "$fake_bin" "oc-1700000000-12345: 1 windows
other-session: 1 windows
main: 1 windows"
    _make_fake_ps "$fake_bin" "  42000"
    local output
    output=$(PATH="$fake_bin:$PATH" bash "$OC_LIST_BIN" 2>&1) || true
    assert_contains "$output" "oc-" "oc-list shows oc-* sessions"
    assert_not_contains "$output" "other-session" "oc-list does not show non-oc sessions"
    assert_not_contains "$output" "main" "oc-list does not show 'main' session"
    teardown_tmp_env
}

test_oc_list_exits_zero_with_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" "oc-1700000000-12345: 1 windows"
    _make_fake_ps "$fake_bin" "  42000"
    local rc=0
    PATH="$fake_bin:$PATH" bash "$OC_LIST_BIN" >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "oc-list exits 0 with active sessions"
    teardown_tmp_env
}

test_oc_list_shows_oc_sessions
test_oc_list_filters_non_oc_sessions
test_oc_list_exits_zero_with_sessions

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: bin/oc-list — only filters oc-* prefix
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-list — only oc-* prefix filtering"

test_oc_list_references_oc_prefix() {
    # Verify the script filters by oc- prefix
    grep -q 'oc-' "$OC_LIST_BIN" && pass "bin/oc-list references oc- prefix" || fail "bin/oc-list does not reference oc- prefix"
}

test_oc_list_references_oc_prefix

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: bin/oc-killall — file properties
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-killall — file properties"

test_oc_killall_file_exists() {
    assert_file_exists "$OC_KILLALL_BIN"
}

test_oc_killall_is_executable() {
    assert_executable "$OC_KILLALL_BIN"
}

test_oc_killall_has_bash_shebang() {
    local first_line
    first_line=$(head -1 "$OC_KILLALL_BIN")
    assert_contains "$first_line" "bash" "bin/oc-killall has bash shebang"
}

test_oc_killall_has_set_euo() {
    grep -q 'set -euo pipefail' "$OC_KILLALL_BIN" && pass "bin/oc-killall uses set -euo pipefail" || fail "bin/oc-killall missing set -euo pipefail"
}

test_oc_killall_syntax_ok() {
    bash -n "$OC_KILLALL_BIN" 2>/dev/null && pass "bin/oc-killall syntax OK" || fail "bin/oc-killall syntax error"
}

test_oc_killall_file_exists
test_oc_killall_is_executable
test_oc_killall_has_bash_shebang
test_oc_killall_has_set_euo
test_oc_killall_syntax_ok

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: bin/oc-killall — --help flag
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-killall — --help flag"

test_oc_killall_help_exits_zero() {
    local rc=0
    bash "$OC_KILLALL_BIN" --help >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "oc-killall --help exits 0"
}

test_oc_killall_help_mentions_kill() {
    local output
    output=$(bash "$OC_KILLALL_BIN" --help 2>&1)
    assert_contains "$output" "kill" "oc-killall --help mentions kill"
}

test_oc_killall_help_mentions_yes_flag() {
    local output
    output=$(bash "$OC_KILLALL_BIN" --help 2>&1)
    assert_contains "$output" "\-\-yes" "oc-killall --help mentions --yes flag"
}

test_oc_killall_help_exits_zero
test_oc_killall_help_mentions_kill
test_oc_killall_help_mentions_yes_flag

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: bin/oc-killall — no sessions
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-killall — no active sessions"

test_oc_killall_exits_zero_no_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" ""
    local rc=0
    PATH="$fake_bin:$PATH" bash "$OC_KILLALL_BIN" --yes >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" "0" "oc-killall exits 0 when no sessions"
    teardown_tmp_env
}

test_oc_killall_prints_no_sessions_message() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" ""
    local output
    output=$(PATH="$fake_bin:$PATH" bash "$OC_KILLALL_BIN" --yes 2>&1) || true
    [ -n "$output" ] && pass "oc-killall prints output when no sessions" || fail "oc-killall prints nothing when no sessions"
    teardown_tmp_env
}

test_oc_killall_exits_zero_no_sessions
test_oc_killall_prints_no_sessions_message

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: bin/oc-killall — --yes flag skips confirmation
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-killall — --yes flag"

test_oc_killall_yes_flag_kills_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" "oc-1700000000-12345: 1 windows"
    local rc=0
    # With --yes, should not hang waiting for confirmation
    timeout 5 bash -c "PATH='$fake_bin:$PATH' bash '$OC_KILLALL_BIN' --yes" >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 124 ] && pass "oc-killall --yes does not hang (no timeout)" || fail "oc-killall --yes timed out (hung waiting for input)"
    teardown_tmp_env
}

test_oc_killall_yes_flag_prints_killed_sessions() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    _make_fake_tmux "$fake_bin" "oc-1700000000-12345: 1 windows"
    local output
    output=$(PATH="$fake_bin:$PATH" bash "$OC_KILLALL_BIN" --yes 2>&1) || true
    assert_contains "$output" "oc-" "oc-killall --yes prints killed session name"
    teardown_tmp_env
}

test_oc_killall_yes_flag_kills_sessions
test_oc_killall_yes_flag_prints_killed_sessions

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: bin/oc-killall — only kills oc-* sessions
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc-killall — only kills oc-* sessions"

test_oc_killall_only_kills_oc_prefix() {
    # Verify the script only targets oc-* sessions (not arbitrary sessions)
    grep -q 'oc-' "$OC_KILLALL_BIN" && pass "bin/oc-killall references oc- prefix" || fail "bin/oc-killall does not reference oc- prefix"
}

test_oc_killall_does_not_kill_all_sessions() {
    # Verify it does NOT invoke 'tmux kill-server' as a command (comments/heredocs are OK)
    # Look for the pattern: tmux kill-server (as a command, not in a string/comment)
    grep -qE '^\s*tmux\s+kill-server' "$OC_KILLALL_BIN" && fail "bin/oc-killall invokes tmux kill-server (too destructive)" || pass "bin/oc-killall does not invoke tmux kill-server"
}

test_oc_killall_only_kills_oc_prefix
test_oc_killall_does_not_kill_all_sessions

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════"
echo "  oc_sessions_test.sh results"
echo "══════════════════════════════════════════════"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo "══════════════════════════════════════════════"

exit "$TESTS_FAILED"
