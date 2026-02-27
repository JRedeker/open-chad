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

# ─── Section 7: Disabled by default ──────────────────────────────────────────

section "Discord disabled by default"

test_discord_disabled_when_no_config_file() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found"; return; fi
    setup_tmp_env
    # No config file at all — simulates a fresh install

    local exit_code=0
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$UPDATE_SH" "1" "0" 2>/dev/null || exit_code=$?

    assert_eq "$exit_code" "0" "update.sh exits 0 with no config file (disabled by default)"
    teardown_tmp_env
}

test_discord_disabled_when_key_absent() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found"; return; fi
    setup_tmp_env
    # Config exists but has no discordPresence key — e.g. after install.sh runs
    echo '{"installer":{"selectedBundles":[]}}' > "$OPEN_CHAD_CONFIG_FILE"

    local exit_code=0
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$UPDATE_SH" "1" "0" 2>/dev/null || exit_code=$?

    assert_eq "$exit_code" "0" "update.sh exits 0 when discordPresence key absent"
    teardown_tmp_env
}

test_discord_disabled_when_enabled_false() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":false}}' > "$OPEN_CHAD_CONFIG_FILE"

    local exit_code=0
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$UPDATE_SH" "1" "0" 2>/dev/null || exit_code=$?

    assert_eq "$exit_code" "0" "update.sh exits 0 when discordPresence.enabled=false"
    teardown_tmp_env
}

test_installer_does_not_write_discord_enabled() {
    # Verify no installer script writes discordPresence.enabled=true
    local found=0
    for f in \
        "$REPO_DIR/install.sh" \
        "$REPO_DIR/lib/wizard.sh" \
        "$REPO_DIR/lib/setup_opencode.sh" \
        "$REPO_DIR/lib/setup_mcp.sh" \
        "$REPO_DIR/lib/update.sh"
    do
        if grep -q 'discordPresence.*enabled.*true\|"discordPresence".*"enabled".*true' "$f" 2>/dev/null; then
            fail "installer file writes discordPresence.enabled=true: $f"
            found=1
        fi
    done
    [ "$found" -eq 0 ] && pass "no installer script enables Discord by default"
}

test_discord_disabled_when_no_config_file
test_discord_disabled_when_key_absent
test_discord_disabled_when_enabled_false
test_installer_does_not_write_discord_enabled

# ─── Section 8: update.sh Client ID fallback chain (rq-MDbiJekK) ─────────────

section "update.sh Client ID fallback chain (rq-MDbiJekK)"

test_update_uses_default_client_id_when_no_custom() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found"; return; fi
    setup_tmp_env
    # Enabled but no clientId — should use built-in default, NOT skip
    echo '{"discordPresence":{"enabled":true}}' > "$OPEN_CHAD_CONFIG_FILE"

    # We can't easily test that update.js was called with the right ID without
    # mocking node, but we CAN test that update.sh does NOT exit early (exit 0
    # before reaching the node call). We verify by checking it doesn't output
    # the "skipping" debug message when OPEN_CHAD_DEBUG=1.
    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_DEBUG=1 \
        DISCORD_RATE_LIMIT_SEC=0 \
        bash "$UPDATE_SH" "1" "0" 2>&1) || true

    assert_not_contains "$result" "clientId not set.*skipping\|clientId not set — skipping" \
        "update.sh does NOT skip when clientId is absent (uses default)"
    teardown_tmp_env
}

test_update_uses_custom_client_id_when_set() {
    if [ ! -f "$UPDATE_SH" ]; then skip "update.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true,"clientId":"9876543210987654321"}}' \
        > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_DEBUG=1 \
        DISCORD_RATE_LIMIT_SEC=0 \
        bash "$UPDATE_SH" "1" "0" 2>&1) || true

    assert_not_contains "$result" "skipping" \
        "update.sh does NOT skip when custom clientId is set"
    teardown_tmp_env
}

test_update_uses_default_client_id_when_no_custom
test_update_uses_custom_client_id_when_set

# ─── Section 9: Default enable — no prompt, no clientId written ──────────────

section "Default enable — zero-prompt path (rq-BlBC0zGJ)"

test_default_enable_writes_enabled_true_no_client_id() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    # Default enable: no DISCORD_CLIENT_ID, no --custom flag
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" enable 2>/dev/null
    local rc=$?

    assert_eq "$rc" "0" "default enable exits 0"

    local enabled
    enabled=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(String((c.discordPresence||{}).enabled));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$enabled" "true" "default enable writes discordPresence.enabled=true"

    local client_id
    client_id=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  const id=(c.discordPresence||{}).clientId;
  process.stdout.write(id===undefined?'absent':String(id));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$client_id" "absent" "default enable does NOT write clientId to config"
    teardown_tmp_env
}

test_default_enable_preserves_existing_keys() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{"theme":"ayu-dark","providers":["zai"]}' > "$OPEN_CHAD_CONFIG_FILE"

    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" enable 2>/dev/null || true

    local theme
    theme=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(c.theme||'missing');
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$theme" "ayu-dark" "default enable preserves existing config keys"
    teardown_tmp_env
}

test_default_enable_writes_enabled_true_no_client_id
test_default_enable_preserves_existing_keys

# ─── Section 9: --custom flag — interactive wizard path ──────────────────────

section "--custom flag — custom Client ID path (rq-9H9rbMve)"

test_custom_enable_writes_client_id() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    DISCORD_CLIENT_ID="9876543210987654321" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" enable --custom --no-prompt 2>/dev/null
    local rc=$?

    assert_eq "$rc" "0" "enable --custom --no-prompt exits 0 with valid ID"

    local client_id
    client_id=$(node -e "
const fs=require('fs');
try {
  const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE'));
  process.stdout.write(String((c.discordPresence||{}).clientId||'missing'));
} catch(e) { process.stdout.write('error'); }
" 2>/dev/null)
    assert_eq "$client_id" "9876543210987654321" "enable --custom writes clientId to config"
    teardown_tmp_env
}

test_custom_enable_invalid_id_exits_nonzero() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{}' > "$OPEN_CHAD_CONFIG_FILE"

    local exit_code=0
    DISCORD_CLIENT_ID="not-a-number" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" enable --custom --no-prompt 2>/dev/null || exit_code=$?

    [ "$exit_code" -ne 0 ] && pass "enable --custom with invalid ID exits non-zero" \
        || fail "enable --custom with invalid ID should exit non-zero (got 0)"
    teardown_tmp_env
}

test_custom_enable_writes_client_id
test_custom_enable_invalid_id_exits_nonzero

# ─── Section 11: status mode reporting (rq-mn3NmUG2) ─────────────────────────

section "status mode reporting — default vs custom (rq-mn3NmUG2)"

test_status_shows_default_mode_when_no_client_id() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true}}' > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --status 2>&1) || true

    assert_contains "$result" "default" \
        "status shows 'default' mode when no clientId in config"
    teardown_tmp_env
}

test_status_shows_custom_mode_when_client_id_set() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true,"clientId":"9876543210987654321"}}' \
        > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        bash "$SETUP_SH" --status 2>&1) || true

    assert_contains "$result" "custom" \
        "status shows 'custom' mode when clientId is set"
    assert_contains "$result" "9876543210987654321" \
        "status shows the custom Client ID"
    teardown_tmp_env
}

test_status_no_tmp_hardcode() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    echo '{"discordPresence":{"enabled":true}}' > "$OPEN_CHAD_CONFIG_FILE"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        bash "$SETUP_SH" --status 2>&1) || true

    # Status should NOT show a hardcoded /tmp path for the lock file
    assert_not_contains "$result" "/tmp/discord-rpc.lock" \
        "status does not show hardcoded /tmp lock path"
    teardown_tmp_env
}

test_status_lock_path_uses_cache_dir() {
    if [ ! -f "$SETUP_SH" ]; then skip "setup.sh not found"; return; fi
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"
    echo '{"discordPresence":{"enabled":true}}' > "$OPEN_CHAD_CONFIG_FILE"
    # Create a lock file in the cache dir to trigger the "Last update" line
    touch "$cache_dir/discord-rpc.lock"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_CACHE_DIR="$cache_dir" \
        bash "$SETUP_SH" --status 2>&1) || true

    # Should show last update (lock file exists) and NOT show /tmp path
    assert_contains "$result" "Last update" \
        "status shows Last update when lock file exists in cache dir"
    assert_not_contains "$result" "/tmp/discord-rpc.lock" \
        "status lock path does not hardcode /tmp"
    teardown_tmp_env
}

test_status_shows_default_mode_when_no_client_id
test_status_shows_custom_mode_when_client_id_set
test_status_no_tmp_hardcode
test_status_lock_path_uses_cache_dir

# ─── Section 8: update.sh wires wsl_bridge.sh ────────────────────────────────

section "update.sh sources wsl_bridge.sh"

UPDATE_SH="$REPO_DIR/lib/discord/update.sh"

test_update_sh_sources_wsl_bridge() {
    # update.sh must source wsl_bridge.sh so _wsl_bridge_ensure is available
    grep -q "wsl_bridge.sh" "$UPDATE_SH" \
        && pass "update.sh references wsl_bridge.sh" \
        || fail "update.sh does not reference wsl_bridge.sh"
}

test_update_sh_calls_wsl_bridge_ensure() {
    # update.sh must call _wsl_bridge_ensure (WSL bridge auto-start)
    grep -q "_wsl_bridge_ensure" "$UPDATE_SH" \
        && pass "update.sh calls _wsl_bridge_ensure" \
        || fail "update.sh does not call _wsl_bridge_ensure"
}

test_update_js_log_file_uses_cache_dir() {
    # update.js LOG_FILE must prefer OPEN_CHAD_CACHE_DIR over a bare os.tmpdir() hardcode.
    # The old pattern was: path.join(os.tmpdir(), 'open-chad-discord.log') with no env check.
    # The new pattern uses OPEN_CHAD_CACHE_DIR as primary with os.tmpdir() as fallback only.
    local update_js="$REPO_DIR/lib/discord/update.js"
    # The primary assignment must reference OPEN_CHAD_CACHE_DIR (not just os.tmpdir())
    grep -q "OPEN_CHAD_CACHE_DIR" "$update_js" \
        && pass "update.js LOG_FILE uses OPEN_CHAD_CACHE_DIR as primary path" \
        || fail "update.js LOG_FILE does not use OPEN_CHAD_CACHE_DIR (still hardcoded to os.tmpdir())"
}

test_update_js_log_file_references_cache_dir_env() {
    # update.js LOG_FILE must reference OPEN_CHAD_CACHE_DIR
    local update_js="$REPO_DIR/lib/discord/update.js"
    grep -q "OPEN_CHAD_CACHE_DIR" "$update_js" \
        && pass "update.js references OPEN_CHAD_CACHE_DIR for log path" \
        || fail "update.js does not reference OPEN_CHAD_CACHE_DIR"
}

test_update_sh_sources_wsl_bridge
test_update_sh_calls_wsl_bridge_ensure
test_update_js_log_file_uses_cache_dir
test_update_js_log_file_references_cache_dir_env

# ─── Section 9: bin/openchad wires WSL bridge auto-start ─────────────────────

section "bin/openchad wires WSL bridge auto-start"

OPENCHAD_BIN="$REPO_DIR/bin/openchad"

test_openchad_sources_wsl_bridge() {
    grep -q "wsl_bridge.sh" "$OPENCHAD_BIN" \
        && pass "bin/openchad sources wsl_bridge.sh" \
        || fail "bin/openchad does not source wsl_bridge.sh"
}

test_openchad_calls_wsl_bridge_ensure() {
    grep -q "_wsl_bridge_ensure" "$OPENCHAD_BIN" \
        && pass "bin/openchad calls _wsl_bridge_ensure" \
        || fail "bin/openchad does not call _wsl_bridge_ensure"
}

test_openchad_uses_bridge_startlock() {
    grep -q "discord-bridge-start.lock" "$OPENCHAD_BIN" \
        && pass "bin/openchad uses discord-bridge-start.lock singleton" \
        || fail "bin/openchad missing discord-bridge-start.lock singleton guard"
}

test_openchad_sources_wsl_bridge
test_openchad_calls_wsl_bridge_ensure
test_openchad_uses_bridge_startlock

# ─── Section 10: discord status shows bridge state on WSL ────────────────────

section "discord status bridge state"

test_status_shows_bridge_ready_on_wsl() {
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"
    # Write enabled config
    cat > "$OPEN_CHAD_CONFIG_FILE" <<'EOF'
{"discordPresence":{"enabled":true}}
EOF
    # Simulate WSL: fake /proc/version with Microsoft kernel
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    # Fake deps in PATH
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"
    echo '#!/bin/sh' > "$fake_bin/socat" && chmod +x "$fake_bin/socat"
    echo '#!/bin/sh' > "$fake_bin/npiperelay.exe" && chmod +x "$fake_bin/npiperelay.exe"
    # Write a live PID (our own shell)
    echo "$$" > "$cache_dir/discord-bridge.pid"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_CACHE_DIR="$cache_dir" \
        OPEN_CHAD_PROC_VERSION="$fake_proc" \
        PATH="$fake_bin:$PATH" \
        bash "$SETUP_SH" --status 2>&1) || true

    assert_contains "$result" "Bridge" "status shows Bridge line on WSL"
    assert_contains "$result" "ready" "status shows bridge ready when PID alive"
    teardown_tmp_env
}

test_status_shows_bridge_missing_deps_on_wsl() {
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"
    cat > "$OPEN_CHAD_CONFIG_FILE" <<'EOF'
{"discordPresence":{"enabled":true}}
EOF
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.90.1-microsoft-standard-WSL2" > "$fake_proc"
    
    # Check if we can isolate from socat
    # On Ubuntu, /bin is a symlink to /usr/bin where socat may be installed
    # setup.sh needs many utilities (dirname, cut, node, etc.) so we can't use minimal PATH
    if command -v socat &>/dev/null; then
        skip "status bridge missing-deps test: socat installed, cannot isolate"
        teardown_tmp_env
        return
    fi
    
    local isolated_path="/usr/bin:/bin"

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_CACHE_DIR="$cache_dir" \
        OPEN_CHAD_PROC_VERSION="$fake_proc" \
        OPEN_CHAD_BRIDGE_NO_GOPATH_FALLBACK=1 \
        PATH="$isolated_path" \
        /bin/bash "$SETUP_SH" --status 2>&1) || true

    assert_contains "$result" "Bridge" "status shows Bridge line when deps missing on WSL"
    assert_contains "$result" "missing" "status shows missing-deps hint"
    teardown_tmp_env
}

test_status_hides_bridge_on_native_linux() {
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"
    cat > "$OPEN_CHAD_CONFIG_FILE" <<'EOF'
{"discordPresence":{"enabled":true}}
EOF
    local fake_proc="$TMP_DIR/proc_version"
    echo "Linux version 5.15.0-generic (Ubuntu)" > "$fake_proc"
    local fake_interop="$TMP_DIR/no_interop"  # does not exist

    local result
    result=$(OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_CACHE_DIR="$cache_dir" \
        OPEN_CHAD_PROC_VERSION="$fake_proc" \
        OPEN_CHAD_WSL_INTEROP="$fake_interop" \
        bash "$SETUP_SH" --status 2>&1) || true

    assert_not_contains "$result" "Bridge" "status hides Bridge line on native Linux"
    teardown_tmp_env
}

test_status_shows_bridge_ready_on_wsl
test_status_shows_bridge_missing_deps_on_wsl
test_status_hides_bridge_on_native_linux

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
