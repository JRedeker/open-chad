#!/usr/bin/env bash
# tests/session_title_test.sh — Unit tests for session_title.sh
# Tests: syntax, epoch extraction, SQLite correlation, no-fallback behavior, edge cases
#
# Usage: bash tests/session_title_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SESSION_TITLE="$REPO_DIR/lib/session_title.sh"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (looking for '$2' in '$1')"; }
assert_not_contains() { ! echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (unexpectedly found '$2' in '$1')"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment ─────────────────────────────────────────────────────────

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_DB="$TMP_DIR/test-opencode.db"
# Use the repo itself as a valid git worktree for testing
TEST_WORKTREE="$REPO_DIR"

# Helper: run session_title.sh with overridden DB path
run_session_title() {
    local pane_path="${1:-$TEST_WORKTREE}"
    local session_name="${2:-}"
    OPENCODE_DB="$TEST_DB" bash "$SESSION_TITLE" "$pane_path" "$session_name" 2>/dev/null || true
}

# Helper: create a fresh test database with the session table
create_test_db() {
    rm -f "$TEST_DB"
    python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute('''
    CREATE TABLE session (
        id TEXT PRIMARY KEY,
        title TEXT,
        directory TEXT,
        parent_id TEXT,
        time_created INTEGER,
        time_updated INTEGER
    )
''')
db.commit()
" "$TEST_DB"
}

# Helper: insert a session row
insert_session() {
    local id="$1"
    local title="$2"
    local directory="$3"
    local parent_id="$4"
    local time_created="$5"
    local time_updated="$6"
    python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
db.execute(
    'INSERT INTO session (id, title, directory, parent_id, time_created, time_updated) VALUES (?, ?, ?, ?, ?, ?)',
    (sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5] if sys.argv[5] != 'NULL' else None, int(sys.argv[6]), int(sys.argv[7]))
)
db.commit()
" "$TEST_DB" "$id" "$title" "$directory" "$parent_id" "$time_created" "$time_updated"
}

# ─── Section 1: Script structure ─────────────────────────────────────────────

section "Script structure"

test_file_exists() {
    [ -f "$SESSION_TITLE" ] && pass "session_title.sh exists" || fail "session_title.sh missing"
}

test_is_executable() {
    [ -x "$SESSION_TITLE" ] && pass "session_title.sh is executable" || fail "session_title.sh not executable"
}

test_syntax() {
    bash -n "$SESSION_TITLE" 2>/dev/null && pass "session_title.sh syntax OK" || fail "session_title.sh syntax error"
}

test_set_euo_pipefail() {
    grep -q 'set -euo pipefail' "$SESSION_TITLE" && pass "strict mode enabled" || fail "missing set -euo pipefail"
}

test_file_exists
test_is_executable
test_syntax
test_set_euo_pipefail

# ─── Section 2: Early exits ─────────────────────────────────────────────────

section "Early exits"

test_empty_path_exits_silently() {
    local result
    result=$(OPENCODE_DB="$TEST_DB" bash "$SESSION_TITLE" "" 2>/dev/null || true)
    assert_eq "$result" "" "empty pane_path → empty output"
}

test_missing_db_exits_silently() {
    local result
    result=$(OPENCODE_DB="/nonexistent/path.db" bash "$SESSION_TITLE" "$TEST_WORKTREE" "oc-1700000000-1234" 2>/dev/null || true)
    assert_eq "$result" "" "missing DB → empty output"
}

test_non_git_dir_exits_silently() {
    local result
    result=$(OPENCODE_DB="$TEST_DB" bash "$SESSION_TITLE" "/tmp" "oc-1700000000-1234" 2>/dev/null || true)
    assert_eq "$result" "" "non-git directory → empty output"
}

test_exit_code_zero_on_empty_path() {
    OPENCODE_DB="$TEST_DB" bash "$SESSION_TITLE" "" >/dev/null 2>&1
    assert_eq "$?" "0" "exit code 0 on empty path"
}

test_exit_code_zero_on_missing_db() {
    OPENCODE_DB="/nonexistent/path.db" bash "$SESSION_TITLE" "$TEST_WORKTREE" >/dev/null 2>&1
    assert_eq "$?" "0" "exit code 0 on missing DB"
}

test_empty_path_exits_silently
test_missing_db_exits_silently
test_non_git_dir_exits_silently
test_exit_code_zero_on_empty_path
test_exit_code_zero_on_missing_db

# ─── Section 3: Epoch extraction from session name ───────────────────────────

section "Epoch extraction from session name"

# Test the regex extraction logic directly
extract_epoch() {
    local session_name="$1"
    local launch_epoch=""
    if [[ "$session_name" =~ ^oc-([0-9]+)- ]]; then
        launch_epoch="${BASH_REMATCH[1]}"
    fi
    echo "$launch_epoch"
}

test_extract_standard_name() {
    local epoch
    epoch=$(extract_epoch "oc-1700000000-12345")
    assert_eq "$epoch" "1700000000" "standard name: oc-1700000000-12345 → 1700000000"
}

test_extract_different_pid() {
    local epoch
    epoch=$(extract_epoch "oc-1735689600-99")
    assert_eq "$epoch" "1735689600" "different pid: oc-1735689600-99 → 1735689600"
}

test_extract_non_oc_name() {
    local epoch
    epoch=$(extract_epoch "my-session")
    assert_eq "$epoch" "" "non-oc name → empty"
}

test_extract_empty_name() {
    local epoch
    epoch=$(extract_epoch "")
    assert_eq "$epoch" "" "empty name → empty"
}

test_extract_oc_no_pid() {
    local epoch
    epoch=$(extract_epoch "oc-1700000000")
    assert_eq "$epoch" "" "oc-<epoch> without trailing -<pid> → empty (no match)"
}

test_extract_standard_name
test_extract_different_pid
test_extract_non_oc_name
test_extract_empty_name
test_extract_oc_no_pid

# ─── Section 4: SQLite timestamp correlation ─────────────────────────────────

section "SQLite timestamp correlation"

test_exact_match_within_window() {
    create_test_db
    # tmux launched at epoch 1700000000 (seconds)
    # OpenCode session created at 1700000005000 (milliseconds) — 5s after launch
    insert_session "ses-001" "My Feature" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_contains "$result" "My Feature" "session created 5s after launch → matched"
}

test_match_at_window_boundary() {
    create_test_db
    # Session created exactly at 120s boundary (1700000000 + 120 = 1700000120 seconds = 1700000120000 ms)
    insert_session "ses-002" "Boundary Session" "$TEST_WORKTREE" "NULL" "1700000120000" "1700000130000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_contains "$result" "Boundary Session" "session at 120s boundary → matched"
}

test_no_match_outside_window() {
    create_test_db
    # Session created 121s after launch — outside the 120s window
    insert_session "ses-003" "Too Late" "$TEST_WORKTREE" "NULL" "1700000121000" "1700000130000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "session 121s after launch → no match"
}

test_no_match_before_launch() {
    create_test_db
    # Session created 1s before launch
    insert_session "ses-004" "Too Early" "$TEST_WORKTREE" "NULL" "1699999999000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "session before launch → no match"
}

test_picks_earliest_in_window() {
    create_test_db
    # Two sessions in the window — should pick the earliest (ASC order)
    insert_session "ses-005" "Second Session" "$TEST_WORKTREE" "NULL" "1700000010000" "1700000020000"
    insert_session "ses-006" "First Session" "$TEST_WORKTREE" "NULL" "1700000002000" "1700000020000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_contains "$result" "First Session" "picks earliest session in window"
}

test_exact_match_within_window
test_match_at_window_boundary
test_no_match_outside_window
test_no_match_before_launch
test_picks_earliest_in_window

# ─── Section 5: No fallback (cross-session bleed prevention) ─────────────────

section "No fallback (cross-session bleed prevention)"

test_no_fallback_when_epoch_misses() {
    create_test_db
    # Session exists but outside the correlation window
    insert_session "ses-010" "Other Session" "$TEST_WORKTREE" "NULL" "1600000000000" "1600000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "no fallback: unrelated session not shown"
}

test_no_fallback_without_session_name() {
    create_test_db
    # Session exists, but no session_name provided → no epoch → no match → empty
    insert_session "ses-011" "Orphan Session" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "")
    assert_eq "$result" "" "no session name → no fallback, empty output"
}

test_no_fallback_non_oc_session() {
    create_test_db
    insert_session "ses-012" "Some Session" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "my-custom-session")
    assert_eq "$result" "" "non-oc session name → no epoch → empty"
}

test_no_fallback_when_epoch_misses
test_no_fallback_without_session_name
test_no_fallback_non_oc_session

# ─── Section 6: Filtering ────────────────────────────────────────────────────

section "Filtering"

test_skips_child_sessions() {
    create_test_db
    # Child session (has parent_id) should be skipped
    insert_session "ses-020" "Child Session" "$TEST_WORKTREE" "ses-parent" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "child session (parent_id set) → skipped"
}

test_skips_empty_title() {
    create_test_db
    insert_session "ses-021" "" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "empty title → skipped"
}

test_skips_wrong_directory() {
    create_test_db
    insert_session "ses-022" "Wrong Dir" "/some/other/project" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_eq "$result" "" "wrong directory → skipped"
}

test_skips_child_sessions
test_skips_empty_title
test_skips_wrong_directory

# ─── Section 7: Output format ────────────────────────────────────────────────

section "Output format"

test_output_has_tmux_formatting() {
    create_test_db
    insert_session "ses-030" "Test Title" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    assert_contains "$result" "#[bold,fg=#BFBDB6]" "output has tmux bold+foreground formatting"
    assert_contains "$result" "Test Title" "output contains the session title"
}

test_output_no_trailing_newline() {
    create_test_db
    insert_session "ses-031" "No Newline" "$TEST_WORKTREE" "NULL" "1700000005000" "1700000010000"
    local result
    result=$(run_session_title "$TEST_WORKTREE" "oc-1700000000-1234")
    local lines
    lines=$(echo "$result" | wc -l)
    assert_eq "$lines" "1" "output is a single line (no trailing newline)"
}

test_output_has_tmux_formatting
test_output_no_trailing_newline

# ─── Section 8: Script structure guards ──────────────────────────────────────

section "Script structure guards"

test_no_fallback_query_in_source() {
    # Ensure the old fallback query pattern is not present
    if grep -q 'ORDER BY time_created DESC' "$SESSION_TITLE"; then
        fail "fallback query still present (ORDER BY time_created DESC)"
    else
        pass "no fallback query in source"
    fi
}

test_no_time_updated_ordering() {
    # Should not order by time_updated (that causes cross-session bleed)
    if grep -q 'ORDER BY time_updated' "$SESSION_TITLE"; then
        fail "ordering by time_updated found (causes bleed)"
    else
        pass "no time_updated ordering"
    fi
}

test_uses_parent_id_filter() {
    grep -q 'parent_id IS NULL' "$SESSION_TITLE" && pass "filters to top-level sessions only" || fail "parent_id IS NULL filter missing"
}

test_no_fallback_query_in_source
test_no_time_updated_ordering
test_uses_parent_id_filter

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
