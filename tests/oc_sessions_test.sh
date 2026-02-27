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
OPENCHAD_BIN="$REPO_DIR/bin/openchad"
OC_BIN="$REPO_DIR/bin/oc"

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

# Helper: fake runtime binaries for executing bin/openchad safely in tests
_make_fake_openchad_runtime() {
    local fake_bin_dir="$1"
    local tmux_log_file="$2"

    mkdir -p "$fake_bin_dir"

    cat > "$fake_bin_dir/tmux" <<EOF
#!/usr/bin/env bash
set -u
printf '%s\n' "\$*" >> "$tmux_log_file"

case "\${1:-}" in
    list-sessions)
        echo 'oc-123: 1 windows (created Mon Jan  1 00:00:00 2024)'
        ;;
esac
exit 0
EOF
    chmod +x "$fake_bin_dir/tmux"

    cat > "$fake_bin_dir/nohup" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin_dir/nohup"

    cat > "$fake_bin_dir/vision" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin_dir/vision"
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
# Rename regression: openchad/oc alias
# ═══════════════════════════════════════════════════════════════════════════════

section "rename regression — openchad/oc alias"

test_oc_list_does_not_reference_old_binary() {
    # oc-list should not reference 'open-chad' as a binary (comments OK)
    if grep -qE 'exec open-chad|command -v open-chad|bin/open-chad' "$OC_LIST_BIN"; then
        fail "bin/oc-list still references old 'open-chad' binary"
    else
        pass "bin/oc-list does not reference old 'open-chad' binary"
    fi
}

test_oc_killall_does_not_reference_old_binary() {
    # oc-killall should not reference 'open-chad' as a binary (comments OK)
    if grep -qE 'exec open-chad|command -v open-chad|bin/open-chad' "$OC_KILLALL_BIN"; then
        fail "bin/oc-killall still references old 'open-chad' binary"
    else
        pass "bin/oc-killall does not reference old 'open-chad' binary"
    fi
}

test_oc_alias_exists() {
    local oc_bin
    oc_bin="$(dirname "$OC_LIST_BIN")/oc"
    if [ -f "$oc_bin" ] && [ -x "$oc_bin" ]; then
        pass "bin/oc alias exists and is executable"
    else
        fail "bin/oc alias missing or not executable"
    fi
}

test_oc_alias_references_openchad() {
    local oc_bin
    oc_bin="$(dirname "$OC_LIST_BIN")/oc"
    grep -q 'openchad' "$oc_bin" 2>/dev/null && pass "bin/oc references openchad" || fail "bin/oc does not reference openchad"
}

test_oc_list_does_not_reference_old_binary
test_oc_killall_does_not_reference_old_binary
test_oc_alias_exists
test_oc_alias_references_openchad

# ═══════════════════════════════════════════════════════════════════════════════
# Session lifecycle regression: openchad exit teardown safety
# ═══════════════════════════════════════════════════════════════════════════════

section "openchad session lifecycle — exit teardown safety"

test_openchad_configures_destroy_unattached() {
    grep -q 'destroy-unattached' "$OPENCHAD_BIN" \
        && pass "bin/openchad configures destroy-unattached teardown" \
        || fail "bin/openchad missing destroy-unattached teardown configuration"
}

test_openchad_executes_session_scoped_destroy_unattached() {
    setup_tmp_env
    local fake_bin="$TMP_DIR/fake_bin"
    local tmux_log="$TMP_DIR/tmux.log"
    touch "$tmux_log"
    _make_fake_openchad_runtime "$fake_bin" "$tmux_log"

    OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        PATH="$fake_bin:$PATH" \
        TERM=dumb \
        bash "$OPENCHAD_BIN" --no-anim >/dev/null 2>&1 || true

    local new_session_line set_option_line session_from_new session_from_set
    new_session_line=$(grep '^new-session -d -s oc-' "$tmux_log" | head -1)
    set_option_line=$(grep '^set-option -t oc-' "$tmux_log" | grep 'destroy-unattached on' | head -1)
    session_from_new=$(echo "$new_session_line" | awk '{print $4}')
    session_from_set=$(echo "$set_option_line" | awk '{print $3}')

    [ -n "$new_session_line" ] \
        && pass "bin/openchad executes tmux new-session for oc-*"
    [ -z "$new_session_line" ] \
        && fail "bin/openchad did not execute tmux new-session"

    [ -n "$set_option_line" ] \
        && pass "bin/openchad executes session-scoped destroy-unattached"
    [ -z "$set_option_line" ] \
        && fail "bin/openchad did not execute session-scoped destroy-unattached"

    if [ -n "$session_from_new" ] && [ -n "$session_from_set" ] && [ "$session_from_new" = "$session_from_set" ]; then
        pass "bin/openchad sets destroy-unattached on the created session"
    else
        fail "bin/openchad destroy-unattached target does not match created session"
    fi

    teardown_tmp_env
}

test_openchad_targets_current_session_for_teardown() {
    grep -qE 'set-option\s+-t\s+"?\$session_name"?\s+destroy-unattached\s+on' "$OPENCHAD_BIN" \
        && pass "bin/openchad targets current session for teardown" \
        || fail "bin/openchad does not set destroy-unattached on current session"
}

test_openchad_does_not_invoke_tmux_kill_server() {
    grep -qE '^\s*tmux\s+kill-server' "$OPENCHAD_BIN" \
        && fail "bin/openchad invokes tmux kill-server (too destructive)" \
        || pass "bin/openchad does not invoke tmux kill-server"
}

test_openchad_warns_once_when_destroy_unattached_unsupported() {
    grep -q 'destroy-unattached.warned' "$OPENCHAD_BIN" \
        && pass "bin/openchad caches destroy-unattached warning to avoid repeated noise" \
        || fail "bin/openchad missing one-time warning cache for destroy-unattached"
}

test_openchad_configures_destroy_unattached
test_openchad_executes_session_scoped_destroy_unattached
test_openchad_targets_current_session_for_teardown
test_openchad_does_not_invoke_tmux_kill_server
test_openchad_warns_once_when_destroy_unattached_unsupported

# ═══════════════════════════════════════════════════════════════════════════════
# Regression: attach/switch + multi-session isolation
# ═══════════════════════════════════════════════════════════════════════════════

section "oc attach/switch + multi-session isolation regression"

test_oc_attach_uses_tmux_attach_session() {
    grep -qE '^\s*exec\s+tmux\s+attach-session' "$OC_BIN" \
        && pass "bin/oc attach path uses tmux attach-session" \
        || fail "bin/oc missing tmux attach-session path"
}

test_oc_switch_uses_tmux_switch_client() {
    grep -qE '^\s*exec\s+tmux\s+switch-client' "$OC_BIN" \
        && pass "bin/oc switch path uses tmux switch-client" \
        || fail "bin/oc missing tmux switch-client path"
}

test_oc_attach_and_switch_filter_oc_sessions() {
    grep -q "grep '\^oc-'" "$OC_BIN" \
        && pass "bin/oc attach/switch filter to oc-* sessions" \
        || fail "bin/oc attach/switch missing oc-* session filtering"
}

test_openchad_uses_unique_oc_session_names() {
    grep -qE 'session_name="oc-\$\(date \+%s\)-\$\$"' "$OPENCHAD_BIN" \
        && pass "bin/openchad keeps per-launch unique oc-* session naming" \
        || fail "bin/openchad missing unique oc-* session naming"
}

test_openchad_teardown_is_session_scoped_not_global() {
    grep -qE 'set-option\s+-t\s+"?\$session_name"?\s+destroy-unattached\s+on' "$OPENCHAD_BIN" \
        && pass "bin/openchad teardown remains session-scoped (multi-session safe)" \
        || fail "bin/openchad teardown is not explicitly session-scoped"
}

test_oc_attach_uses_tmux_attach_session
test_oc_switch_uses_tmux_switch_client
test_oc_attach_and_switch_filter_oc_sessions
test_openchad_uses_unique_oc_session_names
test_openchad_teardown_is_session_scoped_not_global

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
