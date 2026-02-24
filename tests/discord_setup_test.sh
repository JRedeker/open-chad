#!/usr/bin/env bash
# tests/discord_setup_test.sh — TDD red-phase tests for discord CLI/wizard
# Tests: enable/disable/status subcommands, config write/read, CLIENT_ID validation
#
# Usage: bash tests/discord_setup_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SH="$REPO_DIR/lib/discord/setup.sh"
OPEN_CHAD="$REPO_DIR/bin/open-chad"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_eq()           { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got='$1', expected='$2')"; }
assert_contains()     { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (looking for '$2' in: $1)"; }
assert_not_contains() { ! echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (unexpectedly found '$2')"; }
assert_file_exists()  { [ -f "$1" ] && pass "file exists: $1" || fail "file missing: $1"; }
assert_executable()   { [ -x "$1" ] && pass "executable: $1" || fail "not executable: $1"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment Setup ───────────────────────────────────────────────────

TMP_DIR=""

setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    export OPEN_CHAD_CONFIG_DIR="$TMP_DIR/config"
    export OPEN_CHAD_CONFIG_FILE="$TMP_DIR/config/open-chad.json"
    mkdir -p "$TMP_DIR/config"
}

teardown_tmp_env() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
    unset OPEN_CHAD_CONFIG_DIR OPEN_CHAD_CONFIG_FILE TMP_DIR
}

# ─── Section 1: Script exists and is executable ───────────────────────────────

section "Preconditions: setup.sh exists and is executable"

test_setup_sh_exists() {
    [ -f "$SETUP_SH" ] && pass "setup.sh exists" || fail "setup.sh missing at $SETUP_SH"
}

test_setup_sh_executable() {
    [ -x "$SETUP_SH" ] && pass "setup.sh is executable" || fail "setup.sh is not executable"
}

test_setup_sh_syntax() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    bash -n "$SETUP_SH" 2>/dev/null && pass "setup.sh syntax OK" || fail "setup.sh has syntax errors"
}

test_setup_sh_exists
test_setup_sh_executable
test_setup_sh_syntax

# ─── Section 2: CLIENT_ID validation (SC-2) ───────────────────────────────────

section "CLIENT_ID format validation (SC-2)"

# Setup.sh must export a validate_client_id function or inline validation
# We source it and call the function, or pass DISCORD_CLIENT_ID env var

test_valid_client_id_17_digits() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    local result
    result=$(DISCORD_CLIENT_ID="12345678901234567" \
        bash "$SETUP_SH" --validate-id 2>&1) || true
    assert_contains "$result" "valid\|ok\|OK\|Valid\|accepted\|12345678901234567" \
        "17-digit CLIENT_ID accepted as valid"
    teardown_tmp_env
}

test_valid_client_id_19_digits() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    local result
    result=$(DISCORD_CLIENT_ID="1234567890123456789" \
        bash "$SETUP_SH" --validate-id 2>&1) || true
    assert_contains "$result" "valid\|ok\|OK\|Valid\|accepted\|1234567890123456789" \
        "19-digit CLIENT_ID accepted as valid"
    teardown_tmp_env
}

test_invalid_client_id_too_short() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    local result exit_code
    result=$(DISCORD_CLIENT_ID="123456" \
        bash "$SETUP_SH" --validate-id 2>&1) || exit_code=$?
    assert_contains "$result" "invalid\|error\|Error\|Invalid\|must be" \
        "6-digit CLIENT_ID rejected as invalid"
    teardown_tmp_env
}

test_invalid_client_id_non_numeric() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    local result
    result=$(DISCORD_CLIENT_ID="not-a-number" \
        bash "$SETUP_SH" --validate-id 2>&1) || true
    assert_contains "$result" "invalid\|error\|Error\|Invalid\|must be" \
        "non-numeric CLIENT_ID rejected as invalid"
    teardown_tmp_env
}

test_valid_client_id_17_digits
test_valid_client_id_19_digits
test_invalid_client_id_too_short
test_invalid_client_id_non_numeric

# ─── Section 3: enable subcommand writes config (SC-2) ───────────────────────

section "enable subcommand — writes discordPresence config (SC-2)"

test_enable_writes_enabled_true() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    DISCORD_CLIENT_ID="1234567890123456789" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --enable --no-prompt 2>/dev/null || true

    local enabled
    enabled=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(String(c.discordPresence && c.discordPresence.enabled));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$enabled" "true" "enable writes discordPresence.enabled=true to config"
    teardown_tmp_env
}

test_enable_writes_client_id() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    DISCORD_CLIENT_ID="1234567890123456789" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --enable --no-prompt 2>/dev/null || true

    local client_id
    client_id=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(String((c.discordPresence||{}).clientId||'missing'));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$client_id" "1234567890123456789" "enable writes discordPresence.clientId to config"
    teardown_tmp_env
}

test_enable_does_not_clobber_existing_config() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{"theme":"ayu-dark","plugin":["adv"]}' > "$OPEN_CHAD_CONFIG_FILE"

    DISCORD_CLIENT_ID="1234567890123456789" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --enable --no-prompt 2>/dev/null || true

    local theme
    theme=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(c.theme||'missing');
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$theme" "ayu-dark" "enable does not clobber existing config keys"
    teardown_tmp_env
}

test_enable_writes_enabled_true
test_enable_writes_client_id
test_enable_does_not_clobber_existing_config

# ─── Section 4: disable subcommand (SC-3) ────────────────────────────────────

section "disable subcommand — sets enabled=false (SC-3)"

test_disable_sets_enabled_false() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true,"clientId":"1234567890123456789"}}' \
        > "$OPEN_CHAD_CONFIG_FILE"

    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --disable 2>/dev/null || true

    local enabled
    enabled=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(String((c.discordPresence||{}).enabled));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$enabled" "false" "disable sets discordPresence.enabled=false"
    teardown_tmp_env
}

test_disable_when_not_enabled_exits_zero() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --disable 2>/dev/null
    local rc=$?
    assert_eq "$rc" "0" "disable on already-disabled config exits 0"
    teardown_tmp_env
}

test_disable_sets_enabled_false
test_disable_when_not_enabled_exits_zero

# ─── Section 5: status subcommand ────────────────────────────────────────────

section "status subcommand"

test_status_shows_disabled_when_not_configured() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --status 2>&1) || true
    assert_contains "$result" "disabled\|Disabled\|not enabled\|false" \
        "status shows disabled when not configured"
    teardown_tmp_env
}

test_status_shows_enabled_when_configured() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true,"clientId":"1234567890123456789"}}' \
        > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --status 2>&1) || true
    assert_contains "$result" "enabled\|Enabled\|true\|active\|Active" \
        "status shows enabled when discordPresence.enabled=true"
    teardown_tmp_env
}

test_status_shows_disabled_when_not_configured
test_status_shows_enabled_when_configured

# ─── Section 6: Opt-in gate (SC-1) ───────────────────────────────────────────

section "Opt-in gate — no update without config (SC-1)"

UPDATE_SH="$REPO_DIR/lib/discord/update.sh"

test_update_sh_does_not_run_without_config() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found (expected red)"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":false}}' > "$OPEN_CHAD_CONFIG_FILE"

    # Should exit 0 (no-op), should NOT attempt to connect to Discord
    local result exit_code
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$UPDATE_SH" "3" "47" 2>&1) || exit_code=$?

    # When disabled, update.sh should output nothing and exit 0
    assert_eq "${exit_code:-0}" "0" "update.sh exits 0 when disabled"
    assert_not_contains "$result" "error\|Error\|failed\|Failed" \
        "update.sh produces no errors when disabled"
    teardown_tmp_env
}

test_update_sh_does_not_run_without_config

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
