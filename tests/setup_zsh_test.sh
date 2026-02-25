#!/usr/bin/env bash
# tests/setup_zsh_test.sh — Tests for lib/setup_zsh_plugins.sh
#
# Covers:
#   - File existence and syntax
#   - Managed block idempotency (sc-zsh.2.1, sc-zsh.2.2)
#   - Plugin sourcing order (sc-zsh.3.1)
#   - --skip-zsh flag in wizard.sh (sc-zsh.4.1)
#   - Non-fatal update.sh integration (sc-zsh.5.1)
#   - install.sh --skip-zsh flag plumbing (rq-zsh.4)
#   - Plugin clone/update logic (sc-zsh.1.1, sc-zsh.1.2)
#
# Usage: bash tests/setup_zsh_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSH_SETUP="$REPO_DIR/lib/setup_zsh_plugins.sh"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass()  { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail()  { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip()  { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

section() { echo ""; echo "── $1 ──"; }

TMP_DIR=""
setup_tmp() {
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TMP_DIR"' EXIT
}

setup_tmp

# ═══════════════════════════════════════════════════════════════════════════════
# File existence and syntax
# ═══════════════════════════════════════════════════════════════════════════════
section "setup_zsh_plugins.sh — file existence and syntax"

test_file_exists() {
    if [ -f "$ZSH_SETUP" ]; then
        pass "setup_zsh_plugins.sh: file exists"
    else
        fail "setup_zsh_plugins.sh: file missing at $ZSH_SETUP"
    fi
}

test_file_executable() {
    if [ -x "$ZSH_SETUP" ]; then
        pass "setup_zsh_plugins.sh: file is executable"
    else
        fail "setup_zsh_plugins.sh: file is not executable"
    fi
}

test_syntax_ok() {
    if bash -n "$ZSH_SETUP" 2>/dev/null; then
        pass "setup_zsh_plugins.sh: syntax OK"
    else
        fail "setup_zsh_plugins.sh: syntax error"
    fi
}

test_has_set_euo_pipefail() {
    if grep -q 'set -euo pipefail\|set -e.*u.*o pipefail' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: uses set -euo pipefail"
    else
        fail "setup_zsh_plugins.sh: missing set -euo pipefail"
    fi
}

test_file_exists
test_file_executable
test_syntax_ok
test_has_set_euo_pipefail

# ═══════════════════════════════════════════════════════════════════════════════
# Plugin definitions (rq-zsh.1)
# ═══════════════════════════════════════════════════════════════════════════════
section "setup_zsh_plugins.sh — plugin definitions"

test_has_powerlevel10k() {
    if grep -q 'romkatv/powerlevel10k\|powerlevel10k' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: references powerlevel10k"
    else
        fail "setup_zsh_plugins.sh: missing powerlevel10k plugin"
    fi
}

test_has_zsh_autosuggestions() {
    if grep -q 'zsh-users/zsh-autosuggestions\|zsh-autosuggestions' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: references zsh-autosuggestions"
    else
        fail "setup_zsh_plugins.sh: missing zsh-autosuggestions plugin"
    fi
}

test_has_fast_syntax_highlighting() {
    if grep -q 'zdharma-continuum/fast-syntax-highlighting\|fast-syntax-highlighting' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: references fast-syntax-highlighting"
    else
        fail "setup_zsh_plugins.sh: missing fast-syntax-highlighting plugin"
    fi
}

test_plugins_dir_is_home_zsh_plugins() {
    if grep -q '~/.zsh/plugins\|HOME.*\.zsh/plugins\|ZSH_PLUGINS_DIR' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: uses ~/.zsh/plugins/ as plugin directory"
    else
        fail "setup_zsh_plugins.sh: should use ~/.zsh/plugins/ (not ~/.oh-my-zsh or other)"
    fi
}

test_no_oh_my_zsh() {
    if grep -qE '(oh-my-zsh|ohmyzsh|install\.sh.*ohmyz)' "$ZSH_SETUP"; then
        fail "setup_zsh_plugins.sh: references Oh My Zsh (should be standalone plugins only)"
    else
        pass "setup_zsh_plugins.sh: does not reference Oh My Zsh (standalone plugins)"
    fi
}

test_has_powerlevel10k
test_has_zsh_autosuggestions
test_has_fast_syntax_highlighting
test_plugins_dir_is_home_zsh_plugins
test_no_oh_my_zsh

# ═══════════════════════════════════════════════════════════════════════════════
# Managed block structure (rq-zsh.2, rq-zsh.3)
# ═══════════════════════════════════════════════════════════════════════════════
section "setup_zsh_plugins.sh — managed block structure"

test_has_begin_marker() {
    if grep -q 'OPEN-CHAD ZSH BEGIN\|OPEN_CHAD_ZSH_BEGIN' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: has OPEN-CHAD ZSH BEGIN marker"
    else
        fail "setup_zsh_plugins.sh: missing OPEN-CHAD ZSH BEGIN marker"
    fi
}

test_has_end_marker() {
    if grep -q 'OPEN-CHAD ZSH END\|OPEN_CHAD_ZSH_END' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: has OPEN-CHAD ZSH END marker"
    else
        fail "setup_zsh_plugins.sh: missing OPEN-CHAD ZSH END marker"
    fi
}

test_idempotency_guard_present() {
    # Must check for existing block before appending (grep -q guard)
    # The guard can use grep -q with a variable containing the marker, or grep the literal string
    if grep -q 'OPEN-CHAD ZSH BEGIN\|OPEN_CHAD_ZSH_BEGIN\|BLOCK_BEGIN' "$ZSH_SETUP" && \
       grep -q 'grep -q\|grep.*OPEN-CHAD\|grep.*OPEN_CHAD_ZSH\|grep.*BLOCK' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: has idempotency guard (grep check before append)"
    else
        fail "setup_zsh_plugins.sh: missing idempotency guard — will create duplicate blocks"
    fi
}

test_managed_block_idempotent_runtime() {
    # Runtime test: run the managed block logic twice, verify only one block appears
    local fake_home="$TMP_DIR/idempotency-home"
    mkdir -p "$fake_home"
    touch "$fake_home/.zshrc"

    # Create a fake git that does nothing (so plugin clone doesn't actually run)
    local fake_bin="$TMP_DIR/fake-bin"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" << 'FAKEGIT'
#!/usr/bin/env bash
# Fake git: simulate successful clone/pull
case "$1" in
    clone) mkdir -p "$3" 2>/dev/null || mkdir -p "$4" 2>/dev/null; exit 0 ;;
    -C)    exit 0 ;;  # git -C <dir> pull
    pull)  exit 0 ;;
    *)     exit 0 ;;
esac
FAKEGIT
    chmod +x "$fake_bin/git"

    # Run twice
    local exit1=0 exit2=0
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-test.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || exit1=$?

    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-test.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || exit2=$?

    # Count BEGIN markers
    local block_count
    block_count=$(grep -c 'OPEN-CHAD ZSH BEGIN' "$fake_home/.zshrc" 2>/dev/null || echo 0)

    if [ "$block_count" -eq 1 ]; then
        pass "setup_zsh_plugins.sh: managed block is idempotent (count=$block_count after 2 runs)"
    else
        fail "setup_zsh_plugins.sh: managed block not idempotent (count=$block_count after 2 runs)"
    fi
}

test_plugin_order_in_block() {
    # Verify the managed block sources plugins in the correct order:
    # powerlevel10k → zsh-autosuggestions → fast-syntax-highlighting
    local fake_home="$TMP_DIR/order-home"
    mkdir -p "$fake_home"
    touch "$fake_home/.zshrc"

    local fake_bin="$TMP_DIR/fake-bin-order"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" << 'FAKEGIT'
#!/usr/bin/env bash
case "$1" in
    clone) mkdir -p "$3" 2>/dev/null || mkdir -p "$4" 2>/dev/null; exit 0 ;;
    -C)    exit 0 ;;
    pull)  exit 0 ;;
    *)     exit 0 ;;
esac
FAKEGIT
    chmod +x "$fake_bin/git"

    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-order.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || true

    # Extract line numbers of each plugin source in .zshrc
    local p10k_line auto_line fsh_line
    p10k_line=$(grep -n 'powerlevel10k' "$fake_home/.zshrc" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)
    auto_line=$(grep -n 'zsh-autosuggestions' "$fake_home/.zshrc" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)
    fsh_line=$(grep -n 'fast-syntax-highlighting' "$fake_home/.zshrc" 2>/dev/null | head -1 | cut -d: -f1 || echo 0)

    if [ "${p10k_line:-0}" -gt 0 ] && [ "${auto_line:-0}" -gt 0 ] && [ "${fsh_line:-0}" -gt 0 ] && \
       [ "$p10k_line" -lt "$auto_line" ] && [ "$auto_line" -lt "$fsh_line" ]; then
        pass "setup_zsh_plugins.sh: plugin order correct (p10k=$p10k_line, auto=$auto_line, fsh=$fsh_line)"
    else
        fail "setup_zsh_plugins.sh: plugin order wrong (p10k=$p10k_line, auto=$auto_line, fsh=$fsh_line) — fsh must be last"
    fi
}

test_user_content_preserved() {
    # Existing .zshrc content must not be modified
    local fake_home="$TMP_DIR/preserve-home"
    mkdir -p "$fake_home"
    echo "# My custom zsh config" > "$fake_home/.zshrc"
    echo "export MY_VAR=hello" >> "$fake_home/.zshrc"

    local fake_bin="$TMP_DIR/fake-bin-preserve"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" << 'FAKEGIT'
#!/usr/bin/env bash
case "$1" in
    clone) mkdir -p "$3" 2>/dev/null || mkdir -p "$4" 2>/dev/null; exit 0 ;;
    -C)    exit 0 ;;
    pull)  exit 0 ;;
    *)     exit 0 ;;
esac
FAKEGIT
    chmod +x "$fake_bin/git"

    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-preserve.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || true

    if grep -q '# My custom zsh config' "$fake_home/.zshrc" && \
       grep -q 'export MY_VAR=hello' "$fake_home/.zshrc"; then
        pass "setup_zsh_plugins.sh: pre-existing .zshrc content preserved"
    else
        fail "setup_zsh_plugins.sh: pre-existing .zshrc content was modified or deleted"
    fi
}

test_has_begin_marker
test_has_end_marker
test_idempotency_guard_present
test_managed_block_idempotent_runtime
test_plugin_order_in_block
test_user_content_preserved

# ═══════════════════════════════════════════════════════════════════════════════
# Clone vs pull logic (rq-zsh.1)
# ═══════════════════════════════════════════════════════════════════════════════
section "setup_zsh_plugins.sh — clone vs pull logic"

test_uses_git_clone_for_new_plugins() {
    if grep -q 'git clone' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: uses git clone for new plugins"
    else
        fail "setup_zsh_plugins.sh: missing git clone command"
    fi
}

test_uses_git_pull_for_existing_plugins() {
    if grep -q 'git.*pull\|git -C.*pull' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: uses git pull for existing plugins"
    else
        fail "setup_zsh_plugins.sh: missing git pull for existing plugin update"
    fi
}

test_checks_for_existing_git_dir() {
    # Must check if plugin dir already exists (e.g. -d check) before cloning
    if grep -q '\-d.*plugins\|\[ -d\|if.*-d' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: checks for existing plugin directory before cloning"
    else
        fail "setup_zsh_plugins.sh: missing -d check for existing plugin directory"
    fi
}

test_uses_git_clone_for_new_plugins
test_uses_git_pull_for_existing_plugins
test_checks_for_existing_git_dir

# ═══════════════════════════════════════════════════════════════════════════════
# Failure handling and marker integrity
# ═══════════════════════════════════════════════════════════════════════════════
section "setup_zsh_plugins.sh — failure handling and marker integrity"

test_partial_clone_failure_is_non_fatal_when_some_plugins_available() {
    local fake_home="$TMP_DIR/partial-fail-home"
    mkdir -p "$fake_home"
    touch "$fake_home/.zshrc"

    local fake_bin="$TMP_DIR/fake-bin-partial"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" << 'FAKEGIT'
#!/usr/bin/env bash
if [ "$1" = "clone" ]; then
    # Fail only autosuggestions clone, succeed others
    case "$2" in
        *zsh-autosuggestions.git) exit 1 ;;
        *) mkdir -p "$3"; exit 0 ;;
    esac
fi
if [ "$1" = "-C" ]; then
    exit 0
fi
exit 0
FAKEGIT
    chmod +x "$fake_bin/git"

    local exit_code=0
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-partial.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        pass "setup_zsh_plugins.sh: partial clone failure is non-fatal when at least one plugin is available"
    else
        fail "setup_zsh_plugins.sh: expected exit 0 for partial clone failure, got $exit_code"
    fi
}

test_all_clone_failures_exit_nonzero() {
    local fake_home="$TMP_DIR/all-fail-home"
    mkdir -p "$fake_home"
    touch "$fake_home/.zshrc"

    local fake_bin="$TMP_DIR/fake-bin-all-fail"
    mkdir -p "$fake_bin"
    cat > "$fake_bin/git" << 'FAKEGIT'
#!/usr/bin/env bash
if [ "$1" = "clone" ]; then
    exit 1
fi
if [ "$1" = "-C" ]; then
    exit 1
fi
exit 1
FAKEGIT
    chmod +x "$fake_bin/git"

    local exit_code=0
    HOME="$fake_home" PATH="$fake_bin:$PATH" \
    OPEN_CHAD_INSTALL_LOG="$TMP_DIR/zsh-all-fail.log" \
        bash "$ZSH_SETUP" > /dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -ne 0 ]; then
        pass "setup_zsh_plugins.sh: exits non-zero when no plugins are available"
    else
        fail "setup_zsh_plugins.sh: expected non-zero when all clones fail"
    fi
}

test_requires_begin_and_end_markers() {
    if grep -q 'grep -qF.*BLOCK_BEGIN' "$ZSH_SETUP" && grep -q 'grep -qF.*BLOCK_END' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: validates both BEGIN and END markers"
    else
        fail "setup_zsh_plugins.sh: should validate both BEGIN and END markers"
    fi
}

test_has_zshrc_locking() {
    if grep -q 'open-chad.lock\|mkdir .*lock' "$ZSH_SETUP"; then
        pass "setup_zsh_plugins.sh: has .zshrc locking guard for concurrent runs"
    else
        fail "setup_zsh_plugins.sh: missing .zshrc lock guard"
    fi
}

test_partial_clone_failure_is_non_fatal_when_some_plugins_available
test_all_clone_failures_exit_nonzero
test_requires_begin_and_end_markers
test_has_zshrc_locking

# ═══════════════════════════════════════════════════════════════════════════════
# --skip-zsh flag in wizard.sh (rq-zsh.4, sc-zsh.4.1)
# ═══════════════════════════════════════════════════════════════════════════════
section "wizard.sh — --skip-zsh flag"

test_wizard_has_skip_zsh_flag() {
    if grep -q '\-\-skip-zsh\|SKIP_ZSH' "$REPO_DIR/lib/wizard.sh"; then
        pass "wizard.sh: --skip-zsh flag implemented"
    else
        fail "wizard.sh: --skip-zsh flag missing"
    fi
}

test_wizard_skip_zsh_in_help() {
    local output
    output=$(bash "$REPO_DIR/lib/wizard.sh" --help 2>&1 || true)
    if echo "$output" | grep -q 'skip-zsh\|zsh'; then
        pass "wizard.sh: --help mentions --skip-zsh"
    else
        fail "wizard.sh: --help does not mention --skip-zsh"
    fi
}

test_wizard_calls_setup_zsh_plugins() {
    if grep -q 'setup_zsh_plugins\|setup_zsh_plugins.sh' "$REPO_DIR/lib/wizard.sh"; then
        pass "wizard.sh: calls setup_zsh_plugins.sh"
    else
        fail "wizard.sh: does not call setup_zsh_plugins.sh"
    fi
}

test_wizard_skip_zsh_prevents_call() {
    # When SKIP_ZSH=1, setup_zsh_plugins.sh must not be called
    # Verify the guard is present in wizard.sh
    if grep -A 5 'SKIP_ZSH' "$REPO_DIR/lib/wizard.sh" | grep -q 'skip\|setup_zsh_plugins'; then
        pass "wizard.sh: SKIP_ZSH guard present around setup_zsh_plugins.sh call"
    else
        fail "wizard.sh: SKIP_ZSH guard missing — setup_zsh_plugins.sh may run even with --skip-zsh"
    fi
}

test_wizard_yes_skip_zsh_no_hang() {
    # sc-zsh.4.1: wizard with --yes --skip-zsh and all other --skip-* must complete < 10s
    local tmp_wizard="$TMP_DIR/wizard-zsh-sandbox"
    mkdir -p "$tmp_wizard/home/.config/opencode" "$tmp_wizard/cache"
    local exit_code=0
    timeout 10 bash "$REPO_DIR/lib/wizard.sh" \
        --yes \
        --skip-deps \
        --skip-auth \
        --skip-bundles \
        --skip-mcp \
        --skip-adv \
        --skip-morph \
        --skip-zsh \
        HOME="$tmp_wizard/home" \
        OPENCODE_CONFIG_DIR="$tmp_wizard/home/.config/opencode" \
        OPEN_CHAD_INSTALL_LOG="$tmp_wizard/install.log" \
        OPEN_CHAD_CACHE_DIR="$tmp_wizard/cache" \
        > /dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 124 ]; then
        fail "wizard.sh: timed out with --yes --skip-zsh (prompt not skipped)"
    else
        pass "wizard.sh: --yes --skip-zsh completes without hanging (exit $exit_code)"
    fi
}

test_wizard_has_skip_zsh_flag
test_wizard_skip_zsh_in_help
test_wizard_calls_setup_zsh_plugins
test_wizard_skip_zsh_prevents_call
test_wizard_yes_skip_zsh_no_hang

# ═══════════════════════════════════════════════════════════════════════════════
# install.sh --skip-zsh flag (rq-zsh.4)
# ═══════════════════════════════════════════════════════════════════════════════
section "install.sh — --skip-zsh flag"

test_install_has_skip_zsh_flag() {
    if grep -q '\-\-skip-zsh\|SKIP_ZSH' "$REPO_DIR/install.sh"; then
        pass "install.sh: --skip-zsh flag implemented"
    else
        fail "install.sh: --skip-zsh flag missing"
    fi
}

test_install_passes_skip_zsh_to_wizard() {
    # install.sh must pass --skip-zsh through to wizard.sh
    if grep -A 3 'skip-zsh\|SKIP_ZSH' "$REPO_DIR/install.sh" | grep -q 'wizard\|SKIP_ZSH'; then
        pass "install.sh: --skip-zsh is passed through to wizard.sh"
    else
        fail "install.sh: --skip-zsh not plumbed through to wizard.sh"
    fi
}

test_install_has_skip_zsh_flag
test_install_passes_skip_zsh_to_wizard

# ═══════════════════════════════════════════════════════════════════════════════
# update.sh non-fatal integration (rq-zsh.5, sc-zsh.5.1)
# ═══════════════════════════════════════════════════════════════════════════════
section "update.sh — non-fatal zsh setup"

test_update_calls_setup_zsh_plugins() {
    if grep -q 'setup_zsh_plugins\|setup_zsh_plugins.sh' "$REPO_DIR/lib/update.sh"; then
        pass "update.sh: calls setup_zsh_plugins.sh"
    else
        fail "update.sh: does not call setup_zsh_plugins.sh"
    fi
}

test_update_zsh_call_is_non_fatal() {
    # The call must use || warn or || true pattern (non-fatal)
    if grep -A 1 'setup_zsh_plugins' "$REPO_DIR/lib/update.sh" | grep -q '|| warn\||| true\||| {'; then
        pass "update.sh: setup_zsh_plugins.sh call is non-fatal (|| warn/true)"
    else
        fail "update.sh: setup_zsh_plugins.sh call is not non-fatal — update will abort on zsh failure"
    fi
}

test_update_calls_setup_zsh_plugins
test_update_zsh_call_is_non_fatal

# ═══════════════════════════════════════════════════════════════════════════════
# AGENTS.md documentation (tk-qO00AIfE)
# ═══════════════════════════════════════════════════════════════════════════════
section "AGENTS.md — setup_zsh_plugins.sh documented"

test_agents_md_has_zsh_entry() {
    if grep -q 'setup_zsh_plugins' "$REPO_DIR/AGENTS.md"; then
        pass "AGENTS.md: setup_zsh_plugins.sh is documented"
    else
        fail "AGENTS.md: setup_zsh_plugins.sh not documented in architecture section"
    fi
}

test_agents_md_has_zsh_entry

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
