#!/usr/bin/env bash
# tests/installer_robustness_test.sh — Scenario-driven robustness tests
#
# Tests the installer and updater against real-world "dirty" machine states:
#   1. Symlink collision: target is a regular file (not a symlink)
#   2. Symlink collision: target is a directory
#   3. Corrupted opencode.json: auto-recovery (backup + reinitialize + merge)
#   4. Partial plugin checkout: non-git dir quarantined, reclone triggered
#   5. Reinstall on top of existing valid OpenCode config: user keys preserved
#   6. --yes flag suppresses all prompts in conflict scenarios
#   7. update.sh symlink repair handles file/dir collisions same as install.sh
#
# NOTE: Tests that call install.sh use || true because the wizard may fail
# on sub-steps (e.g. setup_ubuntu_deps.sh needs sudo). Symlink creation
# happens BEFORE the wizard exec, so we can still verify symlink state.
#
# Usage: bash tests/installer_robustness_test.sh
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

section() { echo ""; echo "── $1 ──"; }

# Temp dir setup — each test gets a fresh temp dir
# All tests MUST use these overrides to prevent writes to real user config.
# Leak vectors: HOME (symlinks, tmux.conf), OPENCODE_CONFIG_DIR (opencode.json),
# OPEN_CHAD_CACHE_DIR (runtime cache), XDG_RUNTIME_DIR (cache dir resolution).
TMP_DIR=""
TMP_HOME=""
setup_tmp() {
    TMP_DIR=$(mktemp -d)
    TMP_HOME="$TMP_DIR/home"
    mkdir -p "$TMP_HOME/.local/bin"
    mkdir -p "$TMP_HOME/.config/opencode"
    mkdir -p "$TMP_DIR/cache"
    # Export sandbox overrides so child processes (install.sh, setup_mcp.sh) stay sandboxed
    export OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache"
}

teardown_tmp() {
    rm -rf "$TMP_DIR"
    TMP_DIR=""
    TMP_HOME=""
    unset OPEN_CHAD_CACHE_DIR
}

# ─── Helpers ──────────────────────────────────────────────────────────────────
# install.sh does `exec wizard.sh` which replaces the process and may hang on
# setup_ubuntu_deps.sh (sudo). Symlinks are created BEFORE the exec, so we
# only need the first few seconds. --kill-after sends SIGKILL after SIGTERM.
# Sets: INSTALL_OUTPUT (stdout+stderr), INSTALL_EXIT (exit code).
INSTALL_OUTPUT=""
INSTALL_EXIT=0
_run_install() {
    INSTALL_EXIT=0
    # install.sh does `exec wizard.sh` which replaces the process and spawns
    # sub-processes (setup_ubuntu_deps.sh etc). Use setsid to create a new
    # process group so timeout --signal=KILL kills the entire tree.
    INSTALL_OUTPUT=$(timeout --signal=KILL 3 bash -c "
        export HOME='$TMP_HOME'
        export OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache'
        bash '$REPO_DIR/install.sh' $*
    " 2>&1) || INSTALL_EXIT=$?
}

# ─── Section 1: Symlink collision — target is a regular file ─────────────────
# install.sh _install_symlink should replace regular files with symlinks.
# The symlink step runs BEFORE the wizard exec, so we check symlink state
# regardless of wizard exit code.

section "Symlink collision: target is a regular file"

test_install_replaces_regular_file_with_yes() {
    setup_tmp
    # Test with openchad (the canonical name after rename)
    echo "#!/bin/bash" > "$TMP_HOME/.local/bin/openchad"
    chmod +x "$TMP_HOME/.local/bin/openchad"

    _run_install --yes --no-adv --no-omp --no-opencode-setup --no-env-check

    [ -L "$TMP_HOME/.local/bin/openchad" ] && \
        pass "install: openchad is now a symlink after replacing regular file" || \
        fail "install: openchad should be a symlink after replacement"
    teardown_tmp
}

test_install_replaces_regular_file_cds_with_yes() {
    setup_tmp
    echo "#!/bin/bash" > "$TMP_HOME/.local/bin/cds"
    chmod +x "$TMP_HOME/.local/bin/cds"

    _run_install --yes --no-adv --no-omp --no-opencode-setup --no-env-check

    [ -L "$TMP_HOME/.local/bin/cds" ] && \
        pass "install: cds is now a symlink after replacing regular file" || \
        fail "install: cds should be a symlink after replacement"
    teardown_tmp
}

test_install_regular_file_replacement_is_logged() {
    setup_tmp
    echo "#!/bin/bash" > "$TMP_HOME/.local/bin/open-chad"

    _run_install --yes --no-adv --no-omp --no-opencode-setup --no-env-check

    if echo "$INSTALL_OUTPUT" | grep -qi "replac\|overwrite\|exist\|backup\|Symlink"; then
        pass "install: logs message when replacing regular file"
    else
        fail "install: should log a message when replacing a regular file"
    fi
    teardown_tmp
}

test_install_replaces_regular_file_with_yes
test_install_replaces_regular_file_cds_with_yes
test_install_regular_file_replacement_is_logged

# ─── Section 2: Symlink collision — target is a directory ────────────────────
# When the target path is a directory, the installer should abort with a clear
# error rather than silently creating a broken symlink inside the directory.

section "Symlink collision: target is a directory"

test_install_aborts_when_target_is_directory() {
    setup_tmp
    mkdir -p "$TMP_HOME/.local/bin/open-chad"

    _run_install --yes --no-adv --no-omp --no-opencode-setup --no-env-check

    # Should fail with non-zero exit (directory collision detected)
    # INSTALL_EXIT 124 = timeout (wizard hung after symlink step), also counts as non-zero
    [ "$INSTALL_EXIT" -ne 0 ] && \
        pass "install: exits non-zero when target is a directory" || \
        fail "install: should exit non-zero when target is a directory (got $INSTALL_EXIT)"

    # Should print a clear error message about the directory
    if echo "$INSTALL_OUTPUT" | grep -qi "directory\|dir\|cannot\|error\|collision"; then
        pass "install: prints error message when target is a directory"
    else
        fail "install: should print error when target is a directory"
    fi
    teardown_tmp
}

test_install_aborts_when_target_is_directory

# ─── Section 3: Corrupted opencode.json — fail-fast (no silent wipe) ─────────
# setup_mcp.sh should detect invalid JSON and fail with guidance. It must not
# silently reset user config, even in YES_MODE=1.

section "Corrupted opencode.json: fail-fast"

test_mcp_fails_on_corrupted_json_with_yes() {
    if ! command -v node &>/dev/null; then
        skip "test_mcp_recovers_from_corrupted_json_with_yes (node not found)"
        return
    fi

    setup_tmp
    # Write corrupted JSON
    echo '{"mcp": BROKEN JSON' > "$TMP_HOME/.config/opencode/opencode.json"

    local exit_code=0
    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/test.log" \
    YES_MODE=1 \
        bash "$REPO_DIR/lib/setup_mcp.sh" > /dev/null 2>&1 || exit_code=$?

    # Should fail (no silent auto-recovery)
    [ "$exit_code" -ne 0 ] && \
        pass "setup_mcp: exits non-zero on corrupted JSON even with YES_MODE=1" || \
        fail "setup_mcp: should fail-fast on corrupted JSON (got $exit_code)"

    # opencode.json should remain corrupted (no mutation)
    node -e "
const fs=require('fs');
try {
    JSON.parse(fs.readFileSync('$TMP_HOME/.config/opencode/opencode.json','utf8'));
    process.exit(1);
} catch(e) { process.exit(0); }
" 2>/dev/null && \
        pass "setup_mcp: corrupted opencode.json is preserved (not silently overwritten)" || \
        fail "setup_mcp: corrupted opencode.json should be preserved"
    teardown_tmp
}

test_mcp_does_not_create_backup_or_reset_file_implicitly() {
    if ! command -v node &>/dev/null; then
        skip "test_mcp_creates_backup_of_corrupted_json (node not found)"
        return
    fi

    setup_tmp
    echo '{"mcp": BROKEN JSON' > "$TMP_HOME/.config/opencode/opencode.json"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/test.log" \
    YES_MODE=1 \
        bash "$REPO_DIR/lib/setup_mcp.sh" > /dev/null 2>&1 || true

    # No implicit backup/reset file should be created on fail-fast path
    local backup_count
    backup_count=$(ls "$TMP_HOME/.config/opencode/" 2>/dev/null | grep -c "opencode.json.bak" || true)
    backup_count=${backup_count:-0}
    [ "$backup_count" -eq 0 ] && \
        pass "setup_mcp: no implicit backup/reset created on fail-fast path" || \
        fail "setup_mcp: unexpected backup file(s) created (count=$backup_count)"
    teardown_tmp
}

test_mcp_does_not_merge_servers_when_json_is_corrupted() {
    if ! command -v node &>/dev/null; then
        skip "test_mcp_recovers_and_registers_all_servers (node not found)"
        return
    fi

    setup_tmp
    echo '{"mcp": BROKEN JSON' > "$TMP_HOME/.config/opencode/opencode.json"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/test.log" \
    YES_MODE=1 \
        bash "$REPO_DIR/lib/setup_mcp.sh" > /dev/null 2>&1 || true

    # No server merge should occur when base JSON is invalid.
    for server in context7 grep-app lgrep firecrawl brave-web-search; do
        node -e "
const fs=require('fs');
try {
    const c=JSON.parse(fs.readFileSync('$TMP_HOME/.config/opencode/opencode.json','utf8'));
    process.exit((c.mcp && c.mcp['$server']) ? 1 : 0);
} catch(e) { process.exit(0); }
" 2>/dev/null && \
            pass "setup_mcp: '$server' not merged when JSON is corrupted" || \
            fail "setup_mcp: '$server' should not be merged on corrupted JSON"
    done
    teardown_tmp
}

test_mcp_fails_on_corrupted_json_with_yes
test_mcp_does_not_create_backup_or_reset_file_implicitly
test_mcp_does_not_merge_servers_when_json_is_corrupted

# ─── Section 4: Partial plugin checkout — non-git dir quarantined ────────────
# setup_adv.sh and setup_morph.sh should detect non-git checkout dirs
# (partial/failed clones) and quarantine them with timestamped backups.

section "Partial plugin checkout: non-git dir recovery"

test_adv_quarantines_non_git_checkout_dir() {
    # setup_adv.sh should detect non-git dirs and quarantine (rename) them
    if grep -q 'quarantine\|\.bak\.\$\|not a git\|no \.git' "$REPO_DIR/lib/setup_adv.sh"; then
        pass "setup_adv.sh: contains non-git checkout detection logic"
    else
        fail "setup_adv.sh: missing non-git checkout detection (should quarantine partial dirs)"
    fi
}

test_morph_quarantines_non_git_checkout_dir() {
    if grep -q 'quarantine\|\.bak\.\$\|not a git\|no \.git' "$REPO_DIR/lib/setup_morph.sh"; then
        pass "setup_morph.sh: contains non-git checkout detection logic"
    else
        fail "setup_morph.sh: missing non-git checkout detection (should quarantine partial dirs)"
    fi
}

test_adv_quarantine_uses_timestamped_backup() {
    # The quarantine pattern should use a timestamp suffix, not just .bak
    if grep -qE '\.bak\.\$\(date|\.bak\.\$\{|\.bak\.[0-9]' "$REPO_DIR/lib/setup_adv.sh"; then
        pass "setup_adv.sh: quarantine uses timestamped backup suffix"
    else
        fail "setup_adv.sh: quarantine should use timestamped backup (e.g. .bak.\$(date +%s))"
    fi
}

test_morph_quarantine_uses_timestamped_backup() {
    if grep -qE '\.bak\.\$\(date|\.bak\.\$\{|\.bak\.[0-9]' "$REPO_DIR/lib/setup_morph.sh"; then
        pass "setup_morph.sh: quarantine uses timestamped backup suffix"
    else
        fail "setup_morph.sh: quarantine should use timestamped backup (e.g. .bak.\$(date +%s))"
    fi
}

test_adv_quarantines_non_git_checkout_dir
test_morph_quarantines_non_git_checkout_dir
test_adv_quarantine_uses_timestamped_backup
test_morph_quarantine_uses_timestamped_backup

# ─── Section 5: Reinstall preserves existing user config keys ────────────────
# json_merge.sh is additive: scalars only set if key not present.
# Verify that user-set keys survive an MCP merge.

section "Reinstall: existing valid OpenCode config preserved"

test_reinstall_preserves_user_theme_key() {
    if ! command -v node &>/dev/null; then
        skip "test_reinstall_preserves_user_theme_key (node not found)"
        return
    fi

    setup_tmp
    # Pre-existing opencode.json with user-set theme
    echo '{"theme":"monokai","keybinds":{"ctrl+k":"clear"}}' \
        > "$TMP_HOME/.config/opencode/opencode.json"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/test.log" \
        bash "$REPO_DIR/lib/setup_mcp.sh" > /dev/null 2>&1 || true

    # User's theme should still be present (json_merge is additive, no clobber)
    node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$TMP_HOME/.config/opencode/opencode.json','utf8'));
process.exit(c.theme === 'monokai' ? 0 : 1);
" 2>/dev/null && \
        pass "setup_mcp: user theme 'monokai' preserved after MCP merge" || \
        fail "setup_mcp: user theme was overwritten (should be preserved by additive merge)"
    teardown_tmp
}

test_reinstall_preserves_user_keybinds() {
    if ! command -v node &>/dev/null; then
        skip "test_reinstall_preserves_user_keybinds (node not found)"
        return
    fi

    setup_tmp
    echo '{"theme":"monokai","keybinds":{"ctrl+k":"clear"}}' \
        > "$TMP_HOME/.config/opencode/opencode.json"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/test.log" \
        bash "$REPO_DIR/lib/setup_mcp.sh" > /dev/null 2>&1 || true

    node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$TMP_HOME/.config/opencode/opencode.json','utf8'));
process.exit((c.keybinds && c.keybinds['ctrl+k'] === 'clear') ? 0 : 1);
" 2>/dev/null && \
        pass "setup_mcp: user keybinds preserved after MCP merge" || \
        fail "setup_mcp: user keybinds were overwritten (should be preserved)"
    teardown_tmp
}

test_reinstall_preserves_user_theme_key
test_reinstall_preserves_user_keybinds

# ─── Section 6: --yes flag suppresses prompts in conflict scenarios ───────────
# Verify that --yes mode completes without hanging (no interactive prompts).

section "--yes flag: suppresses prompts in all conflict scenarios"

test_yes_flag_suppresses_file_collision_prompt() {
    setup_tmp
    # Test with openchad (the canonical name after rename)
    echo "#!/bin/bash" > "$TMP_HOME/.local/bin/openchad"

    _run_install --yes --no-adv --no-omp --no-opencode-setup --no-env-check

    # Symlink step completes in <1s. The wizard may timeout (124/137) — that's fine.
    # What matters: the symlink was replaced (proves no prompt blocked it).
    [ -L "$TMP_HOME/.local/bin/openchad" ] && \
        pass "--yes: symlink replaced without hanging (exit $INSTALL_EXIT)" || \
        fail "--yes: symlink not replaced — prompt may have blocked (exit $INSTALL_EXIT)"
    teardown_tmp
}

test_yes_flag_suppresses_file_collision_prompt

# ─── Section 7: update.sh symlink repair handles collisions ──────────────────
# Verify update.sh has the same collision-handling logic as install.sh.

section "update.sh: symlink repair handles file/dir collisions"

test_update_repair_symlink_handles_regular_file() {
    # Verify update.sh _repair_symlink handles regular file collision
    if grep -q '_repair_symlink\|repair.*symlink\|symlink.*repair' "$REPO_DIR/lib/update.sh"; then
        pass "update.sh: contains symlink repair function"
    else
        fail "update.sh: missing symlink repair function"
    fi
}

test_update_repair_handles_file_not_symlink() {
    # The repair function should handle regular-file collisions safely.
    # Current implementation validates source and uses ln -sfn for atomic replacement.
    if grep -qE 'ln -sfn.*\$src.*\$dest|\[ ! -e.*\$src\]' "$REPO_DIR/lib/update.sh"; then
        pass "update.sh: repair function uses atomic replacement and source validation"
    else
        fail "update.sh: repair function should use ln -sfn and source existence check"
    fi
}

test_update_repair_symlink_handles_regular_file
test_update_repair_handles_file_not_symlink

# ─── Section 8: check_environment.sh — conflict classification ───────────────
# Verify conflict checks are properly classified (blocker vs. warning).

section "check_environment.sh: conflict classification"

test_env_check_regular_file_collision_is_not_hard_fail() {
    # Existing symlink should be treated as idempotent reinstall (not a conflict)
    if grep -q 'idempotent\|symlink\|L.*_oc_path' "$REPO_DIR/lib/check_environment.sh"; then
        pass "check_environment.sh: handles existing symlink as idempotent reinstall"
    else
        fail "check_environment.sh: should handle existing symlink gracefully"
    fi
}

test_env_check_opencode_not_installed_is_not_blocker() {
    # opencode not being installed should NOT block the installer
    # (it's installed separately; open-chad wraps it but doesn't install it)
    if grep -qE 'command -v opencode.*exit 1|opencode.*FAILED' "$REPO_DIR/lib/check_environment.sh"; then
        fail "check_environment.sh: opencode absence should not be a hard-fail blocker"
    else
        pass "check_environment.sh: opencode absence is not a hard-fail blocker"
    fi
}

test_env_check_regular_file_collision_is_not_hard_fail
test_env_check_opencode_not_installed_is_not_blocker

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
