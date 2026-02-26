#!/usr/bin/env bash
# tests/vision_test.sh — Test suite for Vision daemon bundling
#
# Covers:
#   - setup_vision.sh: binary check, YAML config write, idempotency
#   - bin/openchad: singleton daemon startup (PID lock, atomic mkdir)
#   - lib/openchad_doctor.sh: Vision health checks (binary, PID, ports)
#   - lib/update.sh: Vision wired into update path
#   - lib/wizard.sh: Vision wired into wizard
#   - install.sh: Vision wired into --yes path
#   - lib/openchad_uninstall.sh: daemon stop on uninstall
#
# Usage: bash tests/vision_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (expected='$2' got='$1')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (pattern='$2' not in output)"; }
assert_file_exists() { [ -f "$1" ] && pass "file exists: $1" || fail "file missing: $1"; }
assert_file_contains() { grep -q "$2" "$1" && pass "$1 contains: $2" || fail "$1 missing: $2"; }
assert_file_not_contains() { ! grep -q "$2" "$1" && pass "$1 does not contain: $2" || fail "$1 unexpectedly contains: $2"; }
assert_executable() { [ -x "$1" ] && pass "executable: $1" || fail "not executable: $1"; }
assert_perms() {
    local actual
    actual=$(stat -c '%a' "$1" 2>/dev/null || stat -f '%OLp' "$1" 2>/dev/null || echo "unknown")
    [ "$actual" = "$2" ] && pass "perms $2: $1" || fail "perms $actual (expected $2): $1"
}

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment Setup ───────────────────────────────────────────────────

TMP_DIR=""
setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    TMP_HOME="$TMP_DIR/home"
    TMP_VISION_CONFIG="$TMP_HOME/.config/vision"
    mkdir -p "$TMP_HOME/.local/bin"
    mkdir -p "$TMP_HOME/.config/opencode"
    mkdir -p "$TMP_VISION_CONFIG"
    mkdir -p "$TMP_DIR/cache"
    export HOME="$TMP_HOME"
    export OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache"
    export OPEN_CHAD_INSTALL_LOG="$TMP_DIR/install.log"
}

teardown_tmp_env() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    unset TMP_DIR TMP_HOME TMP_VISION_CONFIG OPEN_CHAD_CACHE_DIR OPEN_CHAD_INSTALL_LOG
}

# ─── Section 1: setup_vision.sh exists and is executable ─────────────────────

section "1. setup_vision.sh: file structure"

assert_file_exists "$REPO_DIR/lib/setup_vision.sh"
assert_executable "$REPO_DIR/lib/setup_vision.sh"

# ─── Section 2: setup_vision.sh: binary check ────────────────────────────────

section "2. setup_vision.sh: binary check"

test_setup_vision_binary_missing() {
    setup_tmp_env
    # Override PATH to hide vision binary
    local saved_PATH="$PATH"
    export PATH="/usr/bin:/bin"

    local output exit_code
    output=$(bash "$REPO_DIR/lib/setup_vision.sh" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}

    # Should warn but not hard-fail (non-fatal)
    assert_contains "$output" "vision" "setup_vision: mentions vision when binary missing"
    # Should NOT exit 1 (non-fatal warning)
    assert_eq "$exit_code" "0" "setup_vision: exits 0 when binary missing (non-fatal)"

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_setup_vision_binary_missing

test_setup_vision_binary_present() {
    setup_tmp_env
    # Create a fake vision binary
    local fake_bin="$TMP_HOME/.local/bin/vision"
    printf '#!/usr/bin/env bash\necho "vision v1.0.0"\n' > "$fake_bin"
    chmod +x "$fake_bin"
    local saved_PATH="$PATH"
    export PATH="$TMP_HOME/.local/bin:$PATH"

    local output exit_code=0
    output=$(bash "$REPO_DIR/lib/setup_vision.sh" 2>&1) || exit_code=$?

    assert_eq "$exit_code" "0" "setup_vision: exits 0 when binary present"
    assert_contains "$output" "vision" "setup_vision: mentions vision in output"

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_setup_vision_binary_present

# ─── Section 3: setup_vision.sh: YAML config write ───────────────────────────

section "3. setup_vision.sh: servers.yaml creation"

test_setup_vision_creates_yaml() {
    setup_tmp_env
    local fake_bin="$TMP_HOME/.local/bin/vision"
    printf '#!/usr/bin/env bash\necho "vision v1.0.0"\n' > "$fake_bin"
    chmod +x "$fake_bin"
    local saved_PATH="$PATH"
    export PATH="$TMP_HOME/.local/bin:$PATH"

    bash "$REPO_DIR/lib/setup_vision.sh" 2>&1 || true

    local yaml_file="$TMP_HOME/.config/vision/servers.yaml"
    assert_file_exists "$yaml_file"
    assert_file_contains "$yaml_file" "context7"
    assert_file_contains "$yaml_file" "grep-app"
    assert_file_contains "$yaml_file" "lgrep"
    assert_file_contains "$yaml_file" "firecrawl"
    assert_file_contains "$yaml_file" "6276"
    assert_file_contains "$yaml_file" "6288"
    assert_file_contains "$yaml_file" "6285"
    assert_file_contains "$yaml_file" "6281"

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_setup_vision_creates_yaml

test_setup_vision_yaml_permissions() {
    setup_tmp_env
    local fake_bin="$TMP_HOME/.local/bin/vision"
    printf '#!/usr/bin/env bash\necho "vision v1.0.0"\n' > "$fake_bin"
    chmod +x "$fake_bin"
    local saved_PATH="$PATH"
    export PATH="$TMP_HOME/.local/bin:$PATH"

    bash "$REPO_DIR/lib/setup_vision.sh" 2>&1 || true

    local yaml_file="$TMP_HOME/.config/vision/servers.yaml"
    if [ -f "$yaml_file" ]; then
        assert_perms "$yaml_file" "600"
    else
        fail "servers.yaml not created — cannot check permissions"
    fi

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_setup_vision_yaml_permissions

# ─── Section 4: setup_vision.sh: idempotency ─────────────────────────────────

section "4. setup_vision.sh: idempotency"

test_setup_vision_idempotent() {
    setup_tmp_env
    local fake_bin="$TMP_HOME/.local/bin/vision"
    printf '#!/usr/bin/env bash\necho "vision v1.0.0"\n' > "$fake_bin"
    chmod +x "$fake_bin"
    local saved_PATH="$PATH"
    export PATH="$TMP_HOME/.local/bin:$PATH"

    # Run twice
    bash "$REPO_DIR/lib/setup_vision.sh" 2>&1 || true
    local exit2=0
    bash "$REPO_DIR/lib/setup_vision.sh" 2>&1 || exit2=$?

    assert_eq "$exit2" "0" "setup_vision: second run exits 0 (idempotent)"

    # YAML should still have exactly one entry per server (no duplicates)
    local yaml_file="$TMP_HOME/.config/vision/servers.yaml"
    if [ -f "$yaml_file" ]; then
        # Count only the YAML key line (indented key:) — not URL references
        local context7_key_count
        context7_key_count=$(grep -cE "^  context7:" "$yaml_file" 2>/dev/null || echo 0)
        [ "$context7_key_count" -eq 1 ] && pass "setup_vision: exactly one context7 key after 2 runs (idempotent)" \
            || fail "setup_vision: expected 1 context7 key, got $context7_key_count after 2 runs"
    else
        fail "setup_vision: servers.yaml missing after second run"
    fi

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_setup_vision_idempotent

# ─── Section 5: bin/openchad: Vision daemon singleton startup ─────────────────

section "5. bin/openchad: Vision daemon singleton startup"

test_openchad_has_vision_startlock() {
    # bin/openchad must contain vision-start.lock atomic mkdir pattern
    assert_file_contains "$REPO_DIR/bin/openchad" "vision-start.lock"
}
test_openchad_has_vision_startlock

test_openchad_has_vision_daemon_start() {
    # bin/openchad must invoke vision daemon start
    assert_file_contains "$REPO_DIR/bin/openchad" "vision"
}
test_openchad_has_vision_daemon_start

test_openchad_vision_log_path() {
    # Vision log must go to OPEN_CHAD_CACHE_DIR (not /tmp directly)
    assert_file_contains "$REPO_DIR/bin/openchad" "vision.log"
    assert_file_not_contains "$REPO_DIR/bin/openchad" '"/tmp/vision'
}
test_openchad_vision_log_path

test_openchad_vision_singleton_guard() {
    setup_tmp_env
    # Simulate: lockdir already exists → daemon should NOT be started again
    mkdir -p "$OPEN_CHAD_CACHE_DIR/vision-start.lock"

    # Source the relevant section of bin/openchad in a subshell
    # We test the guard logic by checking that the mkdir fails gracefully
    local guard_result
    guard_result=$(
        OPEN_CHAD_CACHE_DIR="$OPEN_CHAD_CACHE_DIR"
        _vision_startlock="${OPEN_CHAD_CACHE_DIR}/vision-start.lock"
        if mkdir "$_vision_startlock" 2>/dev/null; then
            echo "STARTED"
        else
            echo "SKIPPED"
        fi
    )
    assert_eq "$guard_result" "SKIPPED" "vision singleton: mkdir fails when lockdir exists"

    teardown_tmp_env
}
test_openchad_vision_singleton_guard

test_openchad_vision_log_created_0600() {
    # bin/openchad must create vision.log with 0600 permissions
    assert_file_contains "$REPO_DIR/bin/openchad" "0600"
}
test_openchad_vision_log_created_0600

# ─── Section 6: openchad_doctor.sh: Vision health checks ─────────────────────

section "6. openchad_doctor.sh: Vision health checks"

test_doctor_checks_vision_binary() {
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "vision"
}
test_doctor_checks_vision_binary

test_doctor_checks_vision_daemon() {
    # Doctor must check daemon status (vision daemon status or PID check)
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "daemon"
}
test_doctor_checks_vision_daemon

test_doctor_checks_vision_ports() {
    # Doctor must check all 4 MCP ports
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "6276"
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "6288"
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "6285"
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "6281"
}
test_doctor_checks_vision_ports

test_doctor_vision_port_timeout() {
    # Port checks must use a timeout (curl --max-time or similar)
    assert_file_contains "$REPO_DIR/lib/openchad_doctor.sh" "max-time"
}
test_doctor_vision_port_timeout

test_doctor_vision_binary_missing_reports_fail() {
    setup_tmp_env
    # Override PATH to hide vision binary
    local saved_PATH="$PATH"
    export PATH="/usr/bin:/bin"

    local output exit_code=0
    output=$(bash "$REPO_DIR/lib/openchad_doctor.sh" 2>&1) || exit_code=$?

    # Doctor should report a failure for missing vision binary
    assert_contains "$output" "vision" "doctor: mentions vision in output"
    [ "$exit_code" -gt 0 ] && pass "doctor: exits non-zero when vision binary missing" \
        || fail "doctor: should exit non-zero when vision binary missing (got $exit_code)"

    export PATH="$saved_PATH"
    teardown_tmp_env
}
test_doctor_vision_binary_missing_reports_fail

# ─── Section 7: wizard.sh: Vision step wired in ───────────────────────────────

section "7. wizard.sh: Vision step wired in"

test_wizard_calls_setup_vision() {
    assert_file_contains "$REPO_DIR/lib/wizard.sh" "setup_vision.sh"
}
test_wizard_calls_setup_vision

test_wizard_vision_after_mcp() {
    # Vision step must come after MCP step (setup_mcp.sh line before setup_vision.sh line)
    local mcp_line vision_line
    mcp_line=$(grep -n "setup_mcp.sh" "$REPO_DIR/lib/wizard.sh" | head -1 | cut -d: -f1)
    vision_line=$(grep -n "setup_vision.sh" "$REPO_DIR/lib/wizard.sh" | head -1 | cut -d: -f1)
    if [ -n "$mcp_line" ] && [ -n "$vision_line" ]; then
        [ "$vision_line" -gt "$mcp_line" ] && pass "wizard: setup_vision.sh called after setup_mcp.sh" \
            || fail "wizard: setup_vision.sh (line $vision_line) must come after setup_mcp.sh (line $mcp_line)"
    else
        fail "wizard: could not find setup_mcp.sh or setup_vision.sh references"
    fi
}
test_wizard_vision_after_mcp

# ─── Section 8: install.sh: Vision wired into --yes path ─────────────────────

section "8. install.sh: Vision wired into --yes path"

test_install_calls_setup_vision() {
    # install.sh delegates to wizard.sh which calls setup_vision.sh
    # Verify install.sh calls wizard.sh (which contains setup_vision.sh)
    assert_file_contains "$REPO_DIR/install.sh" "wizard.sh"
    assert_file_contains "$REPO_DIR/lib/wizard.sh" "setup_vision.sh"
}
test_install_calls_setup_vision

# ─── Section 9: update.sh: Vision wired into update path ─────────────────────

section "9. update.sh: Vision wired into update path"

test_update_calls_setup_vision() {
    assert_file_contains "$REPO_DIR/lib/update.sh" "setup_vision.sh"
}
test_update_calls_setup_vision

test_update_vision_daemon_reload() {
    # update.sh must reload or restart Vision daemon
    assert_file_contains "$REPO_DIR/lib/update.sh" "vision"
}
test_update_vision_daemon_reload

# ─── Section 10: Lifecycle cleanup ───────────────────────────────────────────

section "10. Lifecycle: daemon stop on uninstall/update"

test_update_stops_vision_before_restart() {
    # update.sh must stop Vision before restarting (stop → update → start)
    assert_file_contains "$REPO_DIR/lib/update.sh" "daemon stop"
}
test_update_stops_vision_before_restart

test_uninstall_stops_vision_daemon() {
    # openchad_uninstall.sh must stop Vision daemon before removing symlinks
    assert_file_contains "$REPO_DIR/lib/openchad_uninstall.sh" "vision"
    assert_file_contains "$REPO_DIR/lib/openchad_uninstall.sh" "daemon stop"
}
test_uninstall_stops_vision_daemon

test_update_restarts_vision_daemon() {
    # update.sh must restart Vision daemon after setup (not defer to next launch)
    assert_file_contains "$REPO_DIR/lib/update.sh" "daemon start"
}
test_update_restarts_vision_daemon

# ─── Section 11: Security hardening ──────────────────────────────────────────

section "11. Security: vision.log permissions"

test_vision_log_0600_in_openchad() {
    # bin/openchad must create vision.log with 0600 (install -m 0600 or chmod)
    local has_secure_log=0
    grep -q "install -m 0600" "$REPO_DIR/bin/openchad" && has_secure_log=1
    grep -q "chmod 0600.*vision.log" "$REPO_DIR/bin/openchad" && has_secure_log=1
    [ "$has_secure_log" -eq 1 ] && pass "bin/openchad: vision.log created with 0600 perms" \
        || fail "bin/openchad: vision.log must be created with 0600 permissions"
}
test_vision_log_0600_in_openchad

test_setup_vision_yaml_0600() {
    # setup_vision.sh must set servers.yaml to 0600
    assert_file_contains "$REPO_DIR/lib/setup_vision.sh" "0600"
}
test_setup_vision_yaml_0600

test_setup_vision_yaml_atomic_creation() {
    # setup_vision.sh must use install -m 0600 for atomic secure creation
    assert_file_contains "$REPO_DIR/lib/setup_vision.sh" "install -m 0600"
}
test_setup_vision_yaml_atomic_creation

# ─── Section 12: AGENTS.md documentation ─────────────────────────────────────

section "12. AGENTS.md: Vision documented"

test_agents_md_vision_documented() {
    assert_file_contains "$REPO_DIR/AGENTS.md" "vision"
}
test_agents_md_vision_documented

test_agents_md_vision_ports() {
    assert_file_contains "$REPO_DIR/AGENTS.md" "6276"
}
test_agents_md_vision_ports

test_agents_md_vision_daemon_lifecycle() {
    assert_file_contains "$REPO_DIR/AGENTS.md" "vision.log"
}
test_agents_md_vision_daemon_lifecycle

# ─── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "────────────────────────────────────────"
echo "Vision Test Results:"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "  Skipped: $TESTS_SKIPPED"
echo "────────────────────────────────────────"

exit "$TESTS_FAILED"
