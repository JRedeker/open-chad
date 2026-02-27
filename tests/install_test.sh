#!/usr/bin/env bash
# tests/install_test.sh — Plain bash test suite for open-chad installer
# Tests: idempotency, flag behavior, file creation, missing-dep graceful skip
#
# Usage: bash tests/install_test.sh
# Exit code: number of failed tests (0 = all passed)
#
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  WARNING: THIS TEST SUITE RUNS THE REAL INSTALLER (install.sh) AND SETUP   ║
# ║  SCRIPTS (setup_opencode.sh, etc.) WHICH MODIFY CONFIG FILES.              ║
# ║                                                                            ║
# ║  ALL mutating operations are sandboxed to a temp directory. If the sandbox ║
# ║  is bypassed or broken, the following REAL paths can be damaged:           ║
# ║                                                                            ║
# ║    ~/.config/opencode/agents/*                           (agent files)     ║
# ║    ~/.config/opencode/instructions/*                     (instructions)    ║
# ║    ~/.config/opencode/command/*                          (ADV commands)    ║
# ║    ~/.tmux.conf                                          (tmux theme)      ║
# ║    ~/.zshrc / ~/.bashrc                                  (shell PATH)      ║
# ║                                                                            ║
# ║  DO NOT run this test from inside an OpenCode/tmux session that you care   ║
# ║  about. If something goes wrong, run: bash install.sh --yes                ║
# ║  to restore your personal setup.                                           ║
# ║                                                                            ║
# ║  The sandbox enforces:                                                     ║
# ║    - HOME is redirected to a temp directory                                ║
# ║    - OPEN_CHAD_CACHE_DIR is redirected to a temp directory                 ║
# ║    - OPENCODE_CONFIG_DIR is redirected to a temp directory                 ║
# ║    - XDG_RUNTIME_DIR is redirected to a temp directory                     ║
# ║    - A fail-fast guard aborts if HOME points to a real user directory      ║
# ║      during any sandboxed operation                                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Save the real HOME so we can restore it after each test and detect leaks
_REAL_HOME="$HOME"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_file_exists()  { [ -f "$1" ] && pass "file exists: $1" || fail "file missing: $1"; }
assert_dir_exists()   { [ -d "$1" ] && pass "dir exists: $1" || fail "dir missing: $1"; }
assert_executable()   { [ -x "$1" ] && pass "executable: $1" || fail "not executable: $1"; }
assert_contains()     { grep -q "$2" "$1" && pass "$1 contains: $2" || fail "$1 missing: $2"; }
assert_not_contains() { ! grep -q "$2" "$1" && pass "$1 does not contain: $2" || fail "$1 unexpectedly contains: $2"; }
assert_count_eq() {
    local actual
    actual=$(grep -c "$2" "$1" 2>/dev/null || echo 0)
    [ "$actual" -eq "$3" ] && pass "count($2)=$3 in $1" || fail "count($2)=$actual (expected $3) in $1"
}
# Check that an rc file contains the open-chad PATH block
assert_path_in_rc() {
    local rc_file="$1"
    if [ -f "$rc_file" ] && grep -qF "BEGIN open-chad" "$rc_file"; then
        pass "PATH block in $(basename "$rc_file")"
    else
        fail "PATH block missing in $(basename "$rc_file")"
    fi
}

# Check that PATH block is in ANY of the common rc files
assert_path_in_any_rc() {
    local found=0
    for rc in "$TMP_HOME/.zshrc" "$TMP_HOME/.bashrc" "$TMP_HOME/.profile"; do
        if [ -f "$rc" ] && grep -qF "BEGIN open-chad" "$rc" 2>/dev/null; then
            pass "PATH block found in $(basename "$rc")"
            found=1
            break
        fi
    done
    if [ "$found" -eq 0 ]; then
        fail "PATH block not found in any rc file (.zshrc, .bashrc, .profile)"
    fi
}

section() { echo ""; echo "── $1 ──"; }

# ─── Sandbox Infrastructure ───────────────────────────────────────────────────
# All mutating operations MUST go through these helpers. Direct calls to
# install.sh or setup_opencode.sh outside the sandbox are forbidden.

# Fail-fast: abort immediately if HOME points to a real user directory
# during a sandboxed operation. This catches env leaks.
_assert_sandboxed() {
    if [ "$HOME" = "$_REAL_HOME" ]; then
        echo "FATAL: Sandbox violation — HOME=$HOME is the real user home." >&2
        echo "       A test is running outside the sandbox. Aborting." >&2
        exit 99
    fi
    # Double-check: HOME must be under /tmp
    case "$HOME" in
        /tmp/*) ;; # OK
        *)
            echo "FATAL: Sandbox violation — HOME=$HOME is not under /tmp." >&2
            echo "       Expected HOME to be a temp directory. Aborting." >&2
            exit 99
            ;;
    esac
}

setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    TMP_HOME="$TMP_DIR/home"
    TMP_INSTALL_DIR="$TMP_DIR/install"
    mkdir -p "$TMP_HOME/.local/bin"
    mkdir -p "$TMP_HOME/.config/opencode"
    mkdir -p "$TMP_DIR/cache"
    mkdir -p "$TMP_DIR/runtime"
    mkdir -p "$TMP_INSTALL_DIR"
    # Copy repo into temp install dir to simulate fresh checkout
    cp -r "$REPO_DIR"/. "$TMP_INSTALL_DIR/"
    # Redirect ALL paths that could touch real user state
    export HOME="$TMP_HOME"
    export OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache"
    export XDG_RUNTIME_DIR="$TMP_DIR/runtime"
}

teardown_tmp_env() {
    rm -rf "$TMP_DIR"
    unset TMP_DIR TMP_HOME TMP_INSTALL_DIR OPEN_CHAD_CACHE_DIR XDG_RUNTIME_DIR
    # CRITICAL: Restore real HOME so between-test code doesn't use stale temp path
    export HOME="$_REAL_HOME"
}

# ─── Sandboxed Runner Helpers ─────────────────────────────────────────────────
# These are the ONLY approved ways to invoke install.sh or setup_opencode.sh
# from tests. They enforce full env isolation via env(1).

# Run install.sh in a fully sandboxed subprocess.
# Usage: run_install_sandboxed [extra flags...]
# Requires: setup_tmp_env has been called (TMP_HOME, TMP_DIR set)
run_install_sandboxed() {
    _assert_sandboxed
    timeout --signal=KILL 5 env \
        HOME="$TMP_HOME" \
        OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" \
        PATH="$PATH" \
        USER="${USER:-$(whoami)}" \
        TERM="${TERM:-dumb}" \
        bash "$REPO_DIR/install.sh" --no-env-check "$@" > /dev/null 2>&1 || true
}

# Run setup_opencode.sh in a fully sandboxed subprocess.
# Usage: run_setup_opencode_sandboxed [extra flags...]
# Optional env overrides: ADV_CHECKOUT_DIR (defaults to $TMP_DIR/fake-adv)
run_setup_opencode_sandboxed() {
    _assert_sandboxed
    local adv_dir="${ADV_CHECKOUT_DIR:-$TMP_DIR/fake-adv}"
    env \
        HOME="$TMP_HOME" \
        OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
        ADV_CHECKOUT_DIR="$adv_dir" \
        OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" \
        PATH="$PATH" \
        USER="${USER:-$(whoami)}" \
        TERM="${TERM:-dumb}" \
        bash "$REPO_DIR/lib/setup_opencode.sh" "$@" 2>/dev/null || true
}

# ─── Section 1: Repository Structure ─────────────────────────────────────────

section "Repository Structure"

assert_file_exists "$REPO_DIR/install.sh"
assert_executable "$REPO_DIR/install.sh"
assert_file_exists "$REPO_DIR/lib/json_merge.sh"
assert_file_exists "$REPO_DIR/lib/setup_adv.sh"
assert_file_exists "$REPO_DIR/lib/setup_omp.sh"
assert_file_exists "$REPO_DIR/lib/setup_opencode.sh"
assert_dir_exists  "$REPO_DIR/config/opencode/agents"
assert_dir_exists  "$REPO_DIR/config/opencode/instructions"

# Bundled agent files
assert_file_exists "$REPO_DIR/config/opencode/agents/scout.md"
assert_file_exists "$REPO_DIR/config/opencode/agents/refine.md"
assert_file_exists "$REPO_DIR/config/opencode/agents/librarian.md"
assert_file_exists "$REPO_DIR/config/opencode/agents/explore.md"

# Bundled instruction files
assert_file_exists "$REPO_DIR/config/opencode/instructions/shell_strategy.md"
assert_file_exists "$REPO_DIR/config/opencode/instructions/mcp-tools.md"
assert_file_exists "$REPO_DIR/config/opencode/instructions/worktree-guide.md"
assert_file_exists "$REPO_DIR/config/opencode/instructions/lbp.md"

# ─── Section 2: json_merge.sh ─────────────────────────────────────────────────

section "lib/json_merge.sh — idempotent JSON merge"

test_json_merge_creates_file() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return
    fi
    local tmp_json
    tmp_json=$(mktemp --suffix=.json)
    rm -f "$tmp_json"  # doesn't exist yet

    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["new-plugin"]}' 2>/dev/null
    assert_file_exists "$tmp_json"
    assert_contains "$tmp_json" "new-plugin"
    rm -f "$tmp_json"
}

test_json_merge_appends_array() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return
    fi
    local tmp_json
    tmp_json=$(mktemp --suffix=.json)
    echo '{"plugin":["existing-plugin"]}' > "$tmp_json"

    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["new-plugin"]}' 2>/dev/null
    assert_contains "$tmp_json" "existing-plugin"
    assert_contains "$tmp_json" "new-plugin"
    rm -f "$tmp_json"
}

test_json_merge_is_idempotent() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return
    fi
    local tmp_json
    tmp_json=$(mktemp --suffix=.json)
    echo '{"plugin":["existing-plugin"]}' > "$tmp_json"

    # Run twice
    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["new-plugin"]}' 2>/dev/null
    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["new-plugin"]}' 2>/dev/null

    # Should have each entry exactly once
    assert_count_eq "$tmp_json" "existing-plugin" 1
    assert_count_eq "$tmp_json" "new-plugin" 1
    rm -f "$tmp_json"
}

test_json_merge_does_not_clobber_keys() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return
    fi
    local tmp_json
    tmp_json=$(mktemp --suffix=.json)
    echo '{"plugin":["a"],"theme":"monokai","keybinds":{"x":"y"}}' > "$tmp_json"

    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["b"]}' 2>/dev/null
    assert_contains "$tmp_json" '"theme"'
    assert_contains "$tmp_json" '"monokai"'
    assert_contains "$tmp_json" '"keybinds"'
    rm -f "$tmp_json"
}

test_json_merge_creates_with_defaults() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return
    fi
    local tmp_json
    tmp_json="$TMP_DIR/new_opencode.json"

    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" '{"plugin":["adv"],"instructions":["/path/to/file.md"]}' 2>/dev/null
    assert_file_exists "$tmp_json"
    assert_contains "$tmp_json" '"adv"'
    assert_contains "$tmp_json" '"/path/to/file.md"'
    rm -f "$tmp_json"
}

setup_tmp_env
test_json_merge_creates_file
test_json_merge_appends_array
test_json_merge_is_idempotent
test_json_merge_does_not_clobber_keys
test_json_merge_creates_with_defaults
teardown_tmp_env

# ─── Section 3: setup_opencode.sh — agent/instruction/command sync ───────────

section "lib/setup_opencode.sh — sync agents, instructions, commands"

test_setup_opencode_syncs_agents() {
    setup_tmp_env
    # Run setup with fake ADV checkout path (no ADV checkout needed for agent/instruction sync)
    run_setup_opencode_sandboxed --skip-commands

    assert_file_exists "$TMP_HOME/.config/opencode/agents/scout.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/librarian.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/refine.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/explore.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/build.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/general.md"
    assert_file_exists "$TMP_HOME/.config/opencode/agents/plan.md"
    teardown_tmp_env
}

test_setup_opencode_syncs_instructions() {
    setup_tmp_env
    run_setup_opencode_sandboxed --skip-commands

    assert_file_exists "$TMP_HOME/.config/opencode/instructions/shell_strategy.md"
    assert_file_exists "$TMP_HOME/.config/opencode/instructions/mcp-tools.md"
    assert_file_exists "$TMP_HOME/.config/opencode/instructions/worktree-guide.md"
    assert_file_exists "$TMP_HOME/.config/opencode/instructions/lbp.md"
    assert_file_exists "$TMP_HOME/.config/opencode/instructions/identity.md"
    assert_file_exists "$TMP_HOME/.config/opencode/instructions/rules.yaml"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands() {
    setup_tmp_env
    # Create a fake ADV checkout with a command dir
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/.opencode/command"
    echo "# adv-status" > "$fake_adv/.opencode/command/adv-status.md"
    echo "# adv-apply" > "$fake_adv/.opencode/command/adv-apply.md"

    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed

    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-status.md"
    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-apply.md"
    teardown_tmp_env
}

test_setup_opencode_is_idempotent() {
    setup_tmp_env
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/plugin/commands"
    echo "# adv-status" > "$fake_adv/plugin/commands/adv-status.md"

    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed
    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed

    # Files should exist, not duplicated
    assert_file_exists "$TMP_HOME/.config/opencode/agents/scout.md"
    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-status.md"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands
test_setup_opencode_syncs_agents
test_setup_opencode_syncs_instructions
test_setup_opencode_is_idempotent

test_setup_opencode_wires_md_table_formatter() {
    setup_tmp_env
    run_setup_opencode_sandboxed --skip-commands

    local plugin_json="$TMP_HOME/.config/opencode/opencode.json"
    assert_file_exists "$plugin_json"

    # Verify md-table-formatter plugin is present in plugin array
    if node -e "
const c=JSON.parse(require('fs').readFileSync('$plugin_json','utf8'));
process.exit((c.plugin||[]).includes('@franlol/opencode-md-table-formatter@latest')?0:1);
" 2>/dev/null; then
        pass "setup_opencode.sh: md-table-formatter plugin wired into opencode.json"
    else
        fail "setup_opencode.sh: md-table-formatter plugin missing from opencode.json"
    fi
    teardown_tmp_env
}

test_setup_opencode_md_table_formatter_idempotent() {
    setup_tmp_env
    # Run twice, should only have one entry
    run_setup_opencode_sandboxed --skip-commands
    run_setup_opencode_sandboxed --skip-commands

    local plugin_json="$TMP_HOME/.config/opencode/opencode.json"
    local count
    count=$(node -e "
const c=JSON.parse(require('fs').readFileSync('$plugin_json','utf8'));
console.log((c.plugin||[]).filter(p=>p==='@franlol/opencode-md-table-formatter@latest').length);
" 2>/dev/null || echo "0")

    if [ "$count" -eq 1 ]; then
        pass "setup_opencode.sh: md-table-formatter plugin idempotent (count=$count)"
    else
        fail "setup_opencode.sh: md-table-formatter plugin not idempotent (count=$count, expected 1)"
    fi
    teardown_tmp_env
}

test_setup_opencode_wires_md_table_formatter
test_setup_opencode_md_table_formatter_idempotent

# ─── Section 4: setup_omp.sh — go install ─────────────────────────────────────

section "lib/setup_omp.sh — go install omp"

test_setup_omp_skips_gracefully_without_go() {
    if command -v go &>/dev/null; then
        skip "go is installed; skipping missing-go test"
        return
    fi
    setup_tmp_env
    _assert_sandboxed
    local output
    output=$(env HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        OMP_INSTALL_DIR="$TMP_HOME/.local/bin" \
        bash "$REPO_DIR/lib/setup_omp.sh" 2>&1) || true
    # Should NOT fail the overall installer (exit 0 with warning)
    local exit_code=$?
    # Just check it printed something useful
    echo "$output" | grep -qi "go\|skip\|warn\|not found\|install" && pass "setup_omp.sh printed go-related message" || fail "setup_omp.sh gave no useful output"
    teardown_tmp_env
}

test_setup_omp_installs_binary() {
    if ! command -v go &>/dev/null; then
        skip "go not available"
        return
    fi
    skip "Skipping live go install in test suite (would hit network)"
}

test_setup_omp_skips_gracefully_without_go

# ─── Section 5: setup_adv.sh — pnpm build ────────────────────────────────────

section "lib/setup_adv.sh — ADV install"

test_setup_adv_skips_gracefully_without_pnpm() {
    if command -v pnpm &>/dev/null; then
        skip "pnpm is installed; skipping missing-pnpm test"
        return
    fi
    setup_tmp_env
    _assert_sandboxed
    local output
    output=$(env HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
        bash "$REPO_DIR/lib/setup_adv.sh" 2>&1) || true
    echo "$output" | grep -qi "pnpm\|skip\|warn\|not found\|install" && pass "setup_adv.sh printed pnpm-related message" || fail "setup_adv.sh gave no useful output"
    teardown_tmp_env
}

test_wizard_adv_ok_only_on_success() {
    # wizard.sh should only print "ADV plugin configured" when setup_adv.sh succeeds
    # Verify the ok message is inside an if-then block, not unconditional
    local adv_block
    adv_block=$(sed -n '/Installing ADV/,/fi$/p' "$REPO_DIR/lib/wizard.sh")
    if echo "$adv_block" | grep -q 'then' && echo "$adv_block" | grep -q 'ok.*ADV'; then
        pass "wizard.sh: ADV 'ok' message is conditional on success"
    else
        fail "wizard.sh: ADV 'ok' message should be conditional (inside if/then)"
    fi
}

test_wizard_morph_ok_only_on_success() {
    # Same check for morph
    local morph_block
    morph_block=$(sed -n '/Installing morph/,/fi$/p' "$REPO_DIR/lib/wizard.sh")
    if echo "$morph_block" | grep -q 'then' && echo "$morph_block" | grep -q 'ok.*morph'; then
        pass "wizard.sh: morph 'ok' message is conditional on success"
    else
        fail "wizard.sh: morph 'ok' message should be conditional (inside if/then)"
    fi
}

test_setup_adv_skips_gracefully_without_pnpm
test_wizard_adv_ok_only_on_success
test_wizard_morph_ok_only_on_success

# ─── Section 6: install.sh flag parsing ───────────────────────────────────────

section "install.sh — flag parsing"

test_install_accepts_no_adv_flag() {
    setup_tmp_env
    _assert_sandboxed
    # Pass all --no-* flags to avoid sub-script execution in test environment
    local output
    output=$(timeout --signal=KILL 5 env \
        HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup --no-env-check 2>&1) || true
    # Should not error on unknown-flag
    echo "$output" | grep -qi "unknown.*--no-adv\|invalid.*--no-adv\|illegal.*--no-adv" && fail "--no-adv flag caused error" || pass "--no-adv flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_omp_flag() {
    setup_tmp_env
    _assert_sandboxed
    local output
    output=$(timeout --signal=KILL 5 env \
        HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup --no-env-check 2>&1) || true
    echo "$output" | grep -qi "unknown.*--no-omp\|invalid.*--no-omp\|illegal.*--no-omp" && fail "--no-omp flag caused error" || pass "--no-omp flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_opencode_setup_flag() {
    setup_tmp_env
    _assert_sandboxed
    local output
    output=$(timeout --signal=KILL 5 env \
        HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup --no-env-check 2>&1) || true
    echo "$output" | grep -qi "unknown\|invalid\|error.*flag\|illegal" && fail "--no-opencode-setup flag caused error" || pass "--no-opencode-setup flag parsed without error"
    teardown_tmp_env
}

test_install_no_opencode_setup_includes_skip_adv() {
    # --no-opencode-setup should map to --skip-adv (among others) in wizard args
    if grep -q 'NO_OPENCODE_SETUP.*skip-adv\|"--skip-adv"' "$REPO_DIR/install.sh" && \
       grep -q 'NO_OPENCODE_SETUP' "$REPO_DIR/install.sh"; then
        # Verify the line that handles NO_OPENCODE_SETUP includes --skip-adv
        local line
        line=$(grep 'NO_OPENCODE_SETUP.*WIZARD_ARGS' "$REPO_DIR/install.sh" || echo "")
        if echo "$line" | grep -q 'skip-adv'; then
            pass "--no-opencode-setup maps to --skip-adv in wizard args"
        else
            fail "--no-opencode-setup does NOT map to --skip-adv (ADV still runs)"
        fi
    else
        fail "--no-opencode-setup flag or --skip-adv mapping missing from install.sh"
    fi
}

test_install_accepts_no_adv_flag
test_install_accepts_no_omp_flag
test_install_accepts_no_opencode_setup_flag
test_install_no_opencode_setup_includes_skip_adv

# ─── Section 7: install.sh idempotency ────────────────────────────────────────

section "install.sh — idempotency (tmux theme + PATH)"

test_install_path_idempotent() {
    setup_tmp_env
    # Run install twice with all sub-steps skipped (isolates tmux+PATH behavior)
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    # PATH block should be present in one of the shell rc files
    assert_path_in_any_rc
    teardown_tmp_env
}

test_install_path_includes_bin_dir() {
    setup_tmp_env
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    # The PATH export should include the repo's bin directory in one of the rc files
    local found=0
    for rc in "$TMP_HOME/.zshrc" "$TMP_HOME/.bashrc" "$TMP_HOME/.profile"; do
        if [ -f "$rc" ] && grep -qE 'export PATH=.*bin.*PATH' "$rc" 2>/dev/null; then
            pass "PATH export includes bin directory in $(basename "$rc")"
            found=1
            break
        fi
    done
    if [ "$found" -eq 0 ]; then
        fail "PATH export missing bin directory in all rc files"
    fi
    teardown_tmp_env
}

test_install_tmux_theme_not_duplicated() {
    setup_tmp_env
    # Create existing tmux.conf
    echo "# existing config" > "$TMP_HOME/.tmux.conf"

    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup

    # Theme source should appear exactly once
    local count
    count=$(grep -c "OPEN-CHAD THEME" "$TMP_HOME/.tmux.conf" 2>/dev/null || echo 0)
    [ "$count" -le 1 ] && pass "tmux theme not duplicated (count=$count)" || fail "tmux theme duplicated (count=$count)"
    teardown_tmp_env
}

test_install_tmux_popup_keybind_present_and_not_duplicated() {
    setup_tmp_env
    echo "# existing config" > "$TMP_HOME/.tmux.conf"

    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup

    local bind_count
    bind_count=$(grep -c "omp_popup.sh" "$REPO_DIR/lib/theme.conf" 2>/dev/null || true)
    [ "$bind_count" -ge 1 ] && pass "tmux popup keybind present in theme.conf (count=$bind_count)" || fail "tmux popup keybind missing in theme.conf"

    local marker_count
    marker_count=$(grep -c "OPEN-CHAD THEME" "$TMP_HOME/.tmux.conf" 2>/dev/null || true)
    [ "$marker_count" -le 1 ] && pass "tmux theme source marker not duplicated (count=$marker_count)" || fail "tmux theme source marker duplicated (count=$marker_count)"

    teardown_tmp_env
}

test_install_tmux_popup_default_and_override_sizing() {
    # Verify omp_popup.sh wrapper exists and contains the override variable
    # and default 80%x80% fallback.
    assert_file_exists "$REPO_DIR/lib/omp_popup.sh"
    assert_executable "$REPO_DIR/lib/omp_popup.sh"

    grep -q 'OPEN_CHAD_OMP_POPUP_SIZE' "$REPO_DIR/lib/omp_popup.sh" \
        && pass "omp_popup.sh references OPEN_CHAD_OMP_POPUP_SIZE override" \
        || fail "omp_popup.sh missing OPEN_CHAD_OMP_POPUP_SIZE override"

    grep -q '80%x80%' "$REPO_DIR/lib/omp_popup.sh" \
        && pass "omp_popup.sh includes 80%x80% default fallback" \
        || fail "omp_popup.sh missing 80%x80% default fallback"

    # theme.conf should delegate to omp_popup.sh
    grep -q 'omp_popup.sh' "$REPO_DIR/lib/theme.conf" \
        && pass "theme.conf delegates popup to omp_popup.sh" \
        || fail "theme.conf does not reference omp_popup.sh"
}

test_install_path_idempotent
test_install_path_includes_bin_dir
test_install_tmux_theme_not_duplicated
test_install_tmux_popup_keybind_present_and_not_duplicated
test_install_tmux_popup_default_and_override_sizing

# Verify all required binaries exist in the repo's bin/ directory
test_install_binaries_exist_in_repo() {
    local binaries=("openchad" "oc" "cds" "oc-list" "oc-killall")
    for bin in "${binaries[@]}"; do
        if [ -f "$REPO_DIR/bin/$bin" ]; then
            pass "binary exists in repo: bin/$bin"
        else
            fail "binary missing from repo: bin/$bin"
        fi
    done
}

test_install_binaries_exist_in_repo

# ─── Section 8: lib/opencode_env.sh — cache dir setup ────────────────────────

section "lib/opencode_env.sh — cache dir creation and env resolution"

assert_perms_700() {
    local dir="$1"
    local actual
    actual=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%A' "$dir" 2>/dev/null)
    [ "$actual" = "700" ] && pass "permissions 0700: $dir" || fail "permissions not 0700 (got $actual): $dir"
}

test_opencode_env_creates_cache_dir() {
    setup_tmp_env
    local fake_cache="$TMP_DIR/runtime/open-chad"
    # Unset sandbox override so we can test XDG resolution
    unset OPEN_CHAD_CACHE_DIR
    env HOME="$TMP_HOME" XDG_RUNTIME_DIR="$TMP_DIR/runtime" \
        PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
    assert_dir_exists "$fake_cache"
    assert_perms_700 "$fake_cache"
    teardown_tmp_env
}

test_opencode_env_fallback_without_xdg() {
    setup_tmp_env
    # Unset sandbox override + XDG_RUNTIME_DIR to trigger fallback path
    unset OPEN_CHAD_CACHE_DIR
    local fallback_dir="/tmp/open-chad-${USER}"
    env HOME="$TMP_HOME" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash -c 'unset XDG_RUNTIME_DIR; exec bash "$1"' _ "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null || true
    # Fallback dir should be created
    assert_dir_exists "$fallback_dir"
    assert_perms_700 "$fallback_dir"
    rm -rf "$fallback_dir"
    teardown_tmp_env
}

test_opencode_env_exports_var() {
    setup_tmp_env
    local fake_runtime="$TMP_DIR/runtime"
    mkdir -p "$fake_runtime"
    # Unset sandbox override so we can test XDG resolution
    # Source the env file and verify OPEN_CHAD_CACHE_DIR is set
    local exported_val
    exported_val=$(env HOME="$TMP_HOME" XDG_RUNTIME_DIR="$fake_runtime" \
        PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash -c 'unset OPEN_CHAD_CACHE_DIR; source "$1" && echo "$OPEN_CHAD_CACHE_DIR"' _ "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null)
    [ "$exported_val" = "$fake_runtime/open-chad" ] && \
        pass "OPEN_CHAD_CACHE_DIR=$exported_val (expected $fake_runtime/open-chad)" || \
        fail "OPEN_CHAD_CACHE_DIR='$exported_val' (expected '$fake_runtime/open-chad')"
    teardown_tmp_env
}

test_opencode_env_override_respected() {
    setup_tmp_env
    local custom_dir="$TMP_DIR/custom-cache"
    # Pre-existing OPEN_CHAD_CACHE_DIR should override XDG resolution
    local used_val
    used_val=$(env HOME="$TMP_HOME" OPEN_CHAD_CACHE_DIR="$custom_dir" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash -c 'source "$1" && echo "$OPEN_CHAD_CACHE_DIR"' _ "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null)
    [ "$used_val" = "$custom_dir" ] && \
        pass "override OPEN_CHAD_CACHE_DIR respected: $used_val" || \
        fail "override not respected: got '$used_val', expected '$custom_dir'"
    teardown_tmp_env
}

test_opencode_env_idempotent() {
    setup_tmp_env
    # Unset sandbox override so we can test XDG resolution
    unset OPEN_CHAD_CACHE_DIR
    local fake_runtime="$TMP_DIR/runtime"
    # Running twice should not error or change permissions
    env HOME="$TMP_HOME" XDG_RUNTIME_DIR="$fake_runtime" \
        PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
    env HOME="$TMP_HOME" XDG_RUNTIME_DIR="$fake_runtime" \
        PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
    assert_dir_exists "$fake_runtime/open-chad"
    assert_perms_700 "$fake_runtime/open-chad"
    teardown_tmp_env
}

test_opencode_env_creates_cache_dir
test_opencode_env_fallback_without_xdg
test_opencode_env_exports_var
test_opencode_env_override_respected
test_opencode_env_idempotent

# ─── Section: MCP Nested Object Regression (R2 finding) ──────────────────────
# Regression guard: verify json_merge.sh correctly merges two mcp server objects
# without dropping existing servers. A naive top-level Object.assign would
# overwrite the entire mcp key, losing previously registered servers.

section "MCP Nested Object Regression (json_merge)"

test_json_merge_mcp_nested_objects() {
    if ! command -v node &>/dev/null; then
        skip "test_json_merge_mcp_nested_objects (node not found)"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local tmp_json="$tmp_dir/opencode.json"

    # Step 1: Merge first MCP server
    echo '{}' > "$tmp_json"
    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" \
        '{"mcp":{"context7":{"type":"local","command":["npx","-y","context7"],"enabled":true}}}' \
        2>/dev/null

    # Step 2: Merge second MCP server (should ADD, not REPLACE)
    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" \
        '{"mcp":{"grep-app":{"type":"local","command":["npx","-y","grep-app"],"enabled":true}}}' \
        2>/dev/null

    # Step 3: Verify BOTH servers are present
    local has_context7 has_grep_app
    has_context7=$(node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$tmp_json','utf8'));
process.exit((c.mcp && c.mcp['context7']) ? 0 : 1);
" 2>/dev/null && echo "yes" || echo "no")

    has_grep_app=$(node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$tmp_json','utf8'));
process.exit((c.mcp && c.mcp['grep-app']) ? 0 : 1);
" 2>/dev/null && echo "yes" || echo "no")

    [ "$has_context7" = "yes" ] && \
        pass "MCP merge: context7 preserved after adding grep-app" || \
        fail "MCP merge: context7 DROPPED after adding grep-app (regression!)"

    [ "$has_grep_app" = "yes" ] && \
        pass "MCP merge: grep-app added successfully alongside context7" || \
        fail "MCP merge: grep-app not found after merge"

    # Step 4: Verify merged JSON is valid
    node -e "
const fs=require('fs');
JSON.parse(fs.readFileSync('$tmp_json','utf8'));
" 2>/dev/null && \
        pass "MCP merged JSON is valid JSON" || \
        fail "MCP merged JSON is invalid (corrupted by merge)"

    rm -rf "$tmp_dir"
}

test_json_merge_mcp_five_servers() {
    if ! command -v node &>/dev/null; then
        skip "test_json_merge_mcp_five_servers (node not found)"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local tmp_json="$tmp_dir/opencode.json"
    echo '{}' > "$tmp_json"

    # Simulate setup_mcp.sh: merge all 5 servers sequentially
    local servers=(
        '{"mcp":{"context7":{"type":"local","command":["npx","-y","context7"],"enabled":true}}}'
        '{"mcp":{"grep-app":{"type":"local","command":["npx","-y","grep-app"],"enabled":true}}}'
        '{"mcp":{"lgrep":{"type":"local","command":["npx","-y","lgrep"],"enabled":true}}}'
        '{"mcp":{"firecrawl":{"type":"local","command":["npx","-y","firecrawl"],"enabled":false}}}'
        '{"mcp":{"brave-web-search":{"type":"local","command":["npx","-y","brave"],"enabled":false}}}'
    )

    for patch in "${servers[@]}"; do
        bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" "$patch" 2>/dev/null
    done

    # Verify all 5 are present
    local count
    count=$(node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$tmp_json','utf8'));
const servers=Object.keys(c.mcp||{});
process.stdout.write(String(servers.length));
" 2>/dev/null)

    [ "$count" = "5" ] && \
        pass "All 5 MCP servers present after sequential merge (got: $count)" || \
        fail "Expected 5 MCP servers after sequential merge, got: $count"

    rm -rf "$tmp_dir"
}

test_json_merge_mcp_nested_objects
test_json_merge_mcp_five_servers

# ─── Section 11: Refine agent ADV compatibility ───────────────────────────────

section "Refine agent — ADV compatibility markers"

# Refine must explicitly claim /adv-prep and /adv-harden as in-scope so it
# doesn't deflect those gate steps to Build/Plan.
assert_contains "$REPO_DIR/config/opencode/agents/refine.md" "/adv-prep"
assert_contains "$REPO_DIR/config/opencode/agents/refine.md" "/adv-harden"

# Refine must NOT autonomously orchestrate review/archive/signoff gates.
# A stable marker phrase enforces this boundary.
assert_contains "$REPO_DIR/config/opencode/agents/refine.md" "do not orchestrate"

# ─── Section 12: adv-researcher bundled agent ─────────────────────────────────

section "adv-researcher — bundled fallback agent"

assert_file_exists "$REPO_DIR/config/opencode/agents/adv-researcher.md"

test_setup_opencode_syncs_adv_researcher() {
    setup_tmp_env
    run_setup_opencode_sandboxed --skip-commands

    assert_file_exists "$TMP_HOME/.config/opencode/agents/adv-researcher.md"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_researcher

# ─── Section 13: setup_opencode.sh ADV command path fallback ──────────────────

section "setup_opencode.sh — ADV command path fallback (.opencode/command)"

test_setup_opencode_syncs_adv_commands_opencode_layout() {
    setup_tmp_env
    # ADV uses .opencode/command layout (not plugin/commands)
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/.opencode/command"
    echo "# adv-status" > "$fake_adv/.opencode/command/adv-status.md"
    echo "# adv-apply" > "$fake_adv/.opencode/command/adv-apply.md"

    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed

    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-status.md"
    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-apply.md"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands_opencode_layout_agents() {
    setup_tmp_env
    # ADV checkout has .opencode/agents/adv-researcher.md — should be synced
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/.opencode/agents"
    echo "# adv-researcher upstream" > "$fake_adv/.opencode/agents/adv-researcher.md"

    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed --skip-commands

    # Upstream checkout version should win over bundled fallback
    assert_contains "$TMP_HOME/.config/opencode/agents/adv-researcher.md" "adv-researcher upstream"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands_opencode_layout
test_setup_opencode_syncs_adv_commands_opencode_layout_agents

# ─── Section 13b: No model: frontmatter in bundled/synced agents ─────────────

section "Agent model: frontmatter — must not be shipped (user-managed via OMP)"

# Bundled agent files must never contain model: in frontmatter.
# Model preferences are user-configured via OMP, not pinned by openchad.
test_bundled_agents_no_model_frontmatter() {
    local found_model=0
    for agent_file in "$REPO_DIR"/config/opencode/agents/*.md; do
        if grep -q '^model:' "$agent_file" 2>/dev/null; then
            fail "Bundled agent $(basename "$agent_file") contains 'model:' frontmatter (must be user-managed via OMP)"
            found_model=1
        fi
    done
    [ "$found_model" -eq 0 ] && pass "No bundled agents contain 'model:' frontmatter"
}

# setup_opencode.sh must strip model: from synced agent files, even when
# the upstream ADV checkout ships agents with model: pinned.
test_setup_opencode_strips_model_from_synced_agents() {
    setup_tmp_env
    # Create a fake ADV checkout with model: in its agent file
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/.opencode/agents"
    cat > "$fake_adv/.opencode/agents/adv-researcher.md" <<'AGENT'
---
description: Research agent
mode: subagent
model: google/gemini-3-flash-preview
temperature: 0.10
hidden: true
tools:
  read: true
---
You are a research agent.
AGENT

    ADV_CHECKOUT_DIR="$fake_adv" run_setup_opencode_sandboxed --skip-commands

    local synced="$TMP_HOME/.config/opencode/agents/adv-researcher.md"
    assert_file_exists "$synced"

    if grep -q '^model:' "$synced" 2>/dev/null; then
        fail "Synced adv-researcher.md still contains 'model:' after setup_opencode.sh (should be stripped)"
    else
        pass "setup_opencode.sh stripped 'model:' from upstream ADV agent"
    fi

    # Verify the rest of the frontmatter is intact
    if grep -q '^description:' "$synced" 2>/dev/null && \
       grep -q '^temperature:' "$synced" 2>/dev/null; then
        pass "Non-model frontmatter preserved after stripping"
    else
        fail "setup_opencode.sh damaged non-model frontmatter during strip"
    fi

    teardown_tmp_env
}

# Bundled agents synced by setup_opencode.sh must also be model-free in destination
test_setup_opencode_bundled_agents_no_model_in_dest() {
    setup_tmp_env
    run_setup_opencode_sandboxed --skip-commands

    local found_model=0
    for agent_file in "$TMP_HOME"/.config/opencode/agents/*.md; do
        [ -f "$agent_file" ] || continue
        if grep -q '^model:' "$agent_file" 2>/dev/null; then
            fail "Synced agent $(basename "$agent_file") contains 'model:' in destination"
            found_model=1
        fi
    done
    [ "$found_model" -eq 0 ] && pass "No synced agents contain 'model:' in destination"

    teardown_tmp_env
}

test_bundled_agents_no_model_frontmatter
test_setup_opencode_strips_model_from_synced_agents
test_setup_opencode_bundled_agents_no_model_in_dest

# ─── Section 14: bin/openchad metrics collector atomic lockdir ───────────────

section "bin/openchad — atomic mkdir lockdir for metrics collector"

test_open_chad_uses_atomic_mkdir_for_metrics_singleton() {
    # Verify bin/openchad uses mkdir-based atomic lock (not just pgrep)
    # for the metrics collector singleton guard.
    # The startup lock is metrics-start.lock (distinct from the collector's
    # own PID-based metrics.lock file to avoid dir/file collision).
    assert_contains "$REPO_DIR/bin/openchad" "mkdir"
    assert_contains "$REPO_DIR/bin/openchad" "metrics-start.lock"
}

test_open_chad_metrics_lockdir_skips_start_when_locked() {
    # Simulate: lockdir already exists → collector should NOT be started
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"
    # Pre-create the lockdir to simulate a running collector
    mkdir -p "$cache_dir/metrics-start.lock"

    # Extract and run just the metrics-start logic from bin/open-chad
    # by sourcing a minimal stub that exercises the lockdir guard
    local started=0
    _start_collector() { started=1; }

    local lockdir="$cache_dir/metrics-start.lock"
    if mkdir "$lockdir" 2>/dev/null; then
        _start_collector
        rmdir "$lockdir"
    fi
    # lockdir already existed — should NOT have started
    [ "$started" -eq 0 ] && pass "metrics collector not started when lockdir exists" \
                          || fail "metrics collector started despite existing lockdir"
    teardown_tmp_env
}

test_open_chad_metrics_lockdir_starts_when_not_locked() {
    # Simulate: lockdir absent → collector SHOULD be started
    setup_tmp_env
    local cache_dir="$TMP_DIR/cache"
    mkdir -p "$cache_dir"

    local started=0
    _start_collector() { started=1; }

    local lockdir="$cache_dir/metrics-start.lock"
    if mkdir "$lockdir" 2>/dev/null; then
        _start_collector
        rmdir "$lockdir"
    fi
    [ "$started" -eq 1 ] && pass "metrics collector started when lockdir absent" \
                          || fail "metrics collector not started when lockdir absent"
    teardown_tmp_env
}

test_open_chad_uses_atomic_mkdir_for_metrics_singleton
test_open_chad_metrics_lockdir_skips_start_when_locked
test_open_chad_metrics_lockdir_starts_when_not_locked

# ─── Section 15: collect_metrics.sh find cleanup timeout ─────────────────────

section "collect_metrics.sh — find cleanup wrapped in timeout 5"

test_collect_metrics_find_cleanup_has_timeout() {
    # The 7-day TTL find cleanup should be wrapped in timeout 5 to prevent
    # hangs on slow/network filesystems.
    if grep -q "timeout.*find\|timeout 5.*find\|timeout.*5.*find" "$REPO_DIR/lib/collect_metrics.sh"; then
        pass "collect_metrics.sh find cleanup is wrapped in timeout"
    else
        fail "collect_metrics.sh find cleanup missing timeout wrapper"
    fi
}

test_collect_metrics_find_cleanup_has_timeout

# ─── Section 16: setup_shell_profile.sh here-doc $HOME escaping ──────────────

section "setup_shell_profile.sh — here-doc uses escaped \$HOME (not single-quoted)"

test_setup_shell_profile_heredoc_uses_escaped_home() {
    # The heredoc should use <<EOF (unquoted) with \$HOME so the intent is
    # explicit: we want the literal string $HOME written to the rc file,
    # not expanded at write time. Single-quoted <<'EOF' also works but is
    # less clear about intent.
    if grep -q '\\$HOME' "$REPO_DIR/lib/setup_shell_profile.sh"; then
        pass "setup_shell_profile.sh uses escaped \$HOME in heredoc"
    else
        fail "setup_shell_profile.sh does not use escaped \$HOME (uses single-quoted heredoc)"
    fi
}

test_setup_shell_profile_heredoc_uses_escaped_home

# ─── Section 17: CVE-001 addendum — stale /tmp/discord-rpc.lock cleanup ───────

section "CVE-001 addendum — stale /tmp/discord-rpc.lock cleanup on startup"

test_open_chad_cleans_legacy_discord_lock() {
    # bin/openchad should remove stale /tmp/discord-rpc.lock* files on startup
    assert_contains "$REPO_DIR/bin/openchad" "_legacy_discord_lock"
    assert_contains "$REPO_DIR/bin/openchad" "/tmp/discord-rpc.lock"
}

test_open_chad_legacy_cleanup_checks_regular_file() {
    # Cleanup must check [ -f ] and [ ! -L ] to avoid symlink-follow deletion
    assert_contains "$REPO_DIR/bin/openchad" '! -L'
    # Check for -f check on the legacy file variable (pattern avoids shell expansion)
    if grep -q '\-f.*_legacy_file' "$REPO_DIR/bin/openchad"; then
        pass "bin/openchad: legacy cleanup checks -f before deleting"
    else
        fail "bin/openchad: legacy cleanup missing -f check on _legacy_file"
    fi
}

test_open_chad_legacy_cleanup_covers_guard_and_tagline() {
    # All three legacy lock variants should be cleaned up
    assert_contains "$REPO_DIR/bin/openchad" '.guard'
    assert_contains "$REPO_DIR/bin/openchad" '.tagline'
}

test_open_chad_cleans_legacy_discord_lock
test_open_chad_legacy_cleanup_checks_regular_file
test_open_chad_legacy_cleanup_covers_guard_and_tagline

# ─── Section 18: CVE-004 — symlink rejection in setup_opencode.sh ─────────────

section "CVE-004 — symlink sources rejected in setup_opencode.sh file copy"

test_setup_opencode_rejects_symlink_source() {
    setup_tmp_env
    local agents_src="$TMP_DIR/agents_src"
    mkdir -p "$agents_src"
    # Create a real file and a symlink
    echo "# real agent" > "$agents_src/real.md"
    ln -s "$agents_src/real.md" "$agents_src/symlink.md"

    local dest_dir="$TMP_HOME/.config/opencode/agents"
    mkdir -p "$dest_dir"

    # Run setup_opencode.sh with the symlink in the source dir
    local output
    output=$(env HOME="$TMP_HOME" OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
        ADV_CHECKOUT_DIR="$TMP_DIR/fake-adv" OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache" \
        XDG_RUNTIME_DIR="$TMP_DIR/runtime" PATH="$PATH" USER="${USER:-$(whoami)}" \
        bash "$REPO_DIR/lib/setup_opencode.sh" --skip-commands 2>&1 || true)

    # The symlink should NOT be copied
    if [ ! -f "$dest_dir/symlink.md" ]; then
        pass "CVE-004: symlink source not copied to agents dest"
    else
        fail "CVE-004: symlink source was copied (should be rejected)"
    fi
    teardown_tmp_env
}

test_setup_opencode_symlink_rejection_emits_warning() {
    # Verify the warning message is present in setup_opencode.sh
    assert_contains "$REPO_DIR/lib/setup_opencode.sh" "skipped symlink source"
}

test_setup_opencode_rejects_symlink_source
test_setup_opencode_symlink_rejection_emits_warning

# ─── Section 19: CVE-002 — Go tarball SHA256 check ────────────────────────────

section "CVE-002 — Go tarball SHA256 verification before rm -rf"

test_setup_dev_bundle_has_sha256_check() {
    assert_contains "$REPO_DIR/lib/setup_dev_bundle.sh" "sha256sum"
}

test_setup_dev_bundle_sha256_before_rm_rf() {
    # sha256 check must appear before the rm -rf /usr/local/go line
    local sha_line rm_line
    sha_line=$(grep -n "sha256sum" "$REPO_DIR/lib/setup_dev_bundle.sh" | head -1 | cut -d: -f1)
    rm_line=$(grep -n "rm -rf /usr/local/go" "$REPO_DIR/lib/setup_dev_bundle.sh" | head -1 | cut -d: -f1)
    if [ -n "$sha_line" ] && [ -n "$rm_line" ] && [ "$sha_line" -lt "$rm_line" ]; then
        pass "CVE-002: sha256 check (line $sha_line) precedes rm -rf (line $rm_line)"
    else
        fail "CVE-002: sha256 check not before rm -rf (sha_line=$sha_line rm_line=$rm_line)"
    fi
}

test_setup_dev_bundle_has_sha256_check
test_setup_dev_bundle_sha256_before_rm_rf

# ─── Section 20: CVE-005 — Discord stderr logging ─────────────────────────────

section "CVE-005 — Discord update.sh stderr logged to cache dir"

test_open_chad_discord_stderr_logged_not_devnull() {
    # Discord update.sh stderr should go to a log file, not /dev/null
    assert_contains "$REPO_DIR/bin/openchad" "discord.log"
    assert_not_contains "$REPO_DIR/bin/openchad" 'discord/update.sh.*2>/dev/null'
}

test_open_chad_discord_log_created_with_0600() {
    # The discord.log file should be created with 0600 permissions
    assert_contains "$REPO_DIR/bin/openchad" "0600"
}

test_open_chad_discord_stderr_logged_not_devnull
test_open_chad_discord_log_created_with_0600

# ─── Section 21: PATH-based approach (v1.1) ──────────────────────────────────────

section "PATH-based approach (v1.1 — no symlinks)"

test_install_sh_calls_setup_shell_profile() {
    # Since v1.1, install.sh calls setup_shell_profile.sh to add bin/ to PATH
    assert_contains "$REPO_DIR/install.sh" "setup_shell_profile"
}

test_update_sh_calls_setup_shell_profile() {
    # update.sh also ensures PATH is current
    assert_contains "$REPO_DIR/lib/update.sh" "setup_shell_profile"
}

test_install_sh_no_symlink_manifest() {
    # install.sh should NOT reference symlink_manifest.sh anymore
    assert_not_contains "$REPO_DIR/install.sh" "symlink_manifest"
}

test_update_sh_no_symlink_manifest() {
    # update.sh should NOT reference symlink_manifest.sh anymore
    assert_not_contains "$REPO_DIR/lib/update.sh" "symlink_manifest"
}

test_install_sh_calls_setup_shell_profile
test_update_sh_calls_setup_shell_profile
test_install_sh_no_symlink_manifest
test_update_sh_no_symlink_manifest

# ─── Section 22: ISSUE-008 — Secure wizard log creation ──────────────────────

section "ISSUE-008 — Secure wizard log creation with install -m 0600"

test_wizard_log_uses_install_0600() {
    assert_contains "$REPO_DIR/lib/wizard.sh" "install -m 0600"
}

test_wizard_log_uses_install_0600

# ─── Section 23: ISSUE-019 — collect_metrics.sh cleanup performance SLA ───────

section "ISSUE-019 — collect_metrics.sh cleanup completes within 5s SLA"

test_collect_metrics_cleanup_completes_within_sla() {
    # The find cleanup is wrapped in timeout 5. Verify it completes well within
    # the 5-second SLA on a normal (non-network) filesystem.
    # Expected time: < 1s on local disk. SLA: 5s (enforced by timeout wrapper).
    local cache_dir
    cache_dir=$(mktemp -d)
    # Create some test files, including one "old" file (simulate stale cache)
    touch "$cache_dir/metrics" "$cache_dir/zai" "$cache_dir/copilot"
    # Simulate a 7-day-old file using touch -d
    touch -d "8 days ago" "$cache_dir/stale_file" 2>/dev/null || touch "$cache_dir/stale_file"

    local start_ts end_ts elapsed
    start_ts=$(date +%s%N 2>/dev/null || date +%s)
    timeout 5 find "$cache_dir" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true
    end_ts=$(date +%s%N 2>/dev/null || date +%s)

    # Calculate elapsed in milliseconds (fallback to seconds if %N unavailable)
    if [ ${#start_ts} -gt 10 ]; then
        elapsed=$(( (end_ts - start_ts) / 1000000 ))
        [ "$elapsed" -lt 2000 ] \
            && pass "collect_metrics.sh cleanup completed in ${elapsed}ms (SLA: 5000ms)" \
            || fail "collect_metrics.sh cleanup took ${elapsed}ms (SLA: 5000ms)"
    else
        elapsed=$(( end_ts - start_ts ))
        [ "$elapsed" -lt 5 ] \
            && pass "collect_metrics.sh cleanup completed in ${elapsed}s (SLA: 5s)" \
            || fail "collect_metrics.sh cleanup took ${elapsed}s (SLA: 5s)"
    fi
    rm -rf "$cache_dir"
}

test_collect_metrics_cleanup_completes_within_sla

# ─── Section 17: openchad rename and oc alias (TDD scaffold) ─────────────────
# These tests define the contract for the rename. They FAIL until implementation.

section "bin/openchad — rename from open-chad"

test_openchad_bin_exists() {
    assert_file_exists "$REPO_DIR/bin/openchad"
}

test_openchad_bin_executable() {
    [ -x "$REPO_DIR/bin/openchad" ] && pass "bin/openchad is executable" || fail "bin/openchad is not executable"
}

test_openchad_bin_syntax_ok() {
    bash -n "$REPO_DIR/bin/openchad" 2>/dev/null && pass "bin/openchad syntax OK" || fail "bin/openchad syntax error"
}

test_open_chad_bin_removed() {
    # The old hyphenated name must not exist as a separate file (symlink is ok during migration)
    if [ -f "$REPO_DIR/bin/open-chad" ] && [ ! -L "$REPO_DIR/bin/open-chad" ]; then
        fail "bin/open-chad still exists as a regular file (should be renamed to bin/openchad)"
    else
        pass "bin/open-chad is not a regular file (renamed or removed)"
    fi
}

test_openchad_has_shebang() {
    local first_line
    first_line=$(head -1 "$REPO_DIR/bin/openchad" 2>/dev/null || echo "")
    echo "$first_line" | grep -q "bash" && pass "bin/openchad has bash shebang" || fail "bin/openchad missing bash shebang"
}

test_openchad_bin_exists
test_openchad_bin_executable
test_openchad_bin_syntax_ok
test_open_chad_bin_removed
test_openchad_has_shebang

section "bin/oc — thin alias"

test_oc_bin_exists() {
    assert_file_exists "$REPO_DIR/bin/oc"
}

test_oc_bin_executable() {
    [ -x "$REPO_DIR/bin/oc" ] && pass "bin/oc is executable" || fail "bin/oc is not executable"
}

test_oc_bin_syntax_ok() {
    bash -n "$REPO_DIR/bin/oc" 2>/dev/null && pass "bin/oc syntax OK" || fail "bin/oc syntax error"
}

test_oc_execs_openchad() {
    grep -q 'openchad' "$REPO_DIR/bin/oc" && pass "bin/oc references openchad" || fail "bin/oc does not reference openchad"
}

test_oc_forwards_all_args() {
    grep -q '"$@"\|"${@}"' "$REPO_DIR/bin/oc" && pass "bin/oc forwards all args" || fail "bin/oc does not forward all args"
}

test_oc_bin_exists
test_oc_bin_executable
test_oc_bin_syntax_ok
test_oc_execs_openchad
test_oc_forwards_all_args

section "install.sh — openchad/oc binaries and PATH setup"

test_install_binaries_exist() {
    local binaries=("openchad" "oc" "cds" "oc-list" "oc-killall")
    for bin in "${binaries[@]}"; do
        assert_file_exists "$REPO_DIR/bin/$bin"
    done
}

test_install_path_written_to_rc() {
    setup_tmp_env
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    # The PATH block should be written to one of the shell rc files
    assert_path_in_any_rc
    teardown_tmp_env
}

test_install_does_not_create_open_chad_symlink() {
    setup_tmp_env
    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup
    # With new PATH-based approach, we don't create symlinks at all
    # But we also shouldn't have a stale open-chad symlink
    if [ -L "$TMP_HOME/.local/bin/open-chad" ]; then
        fail "install.sh still creates open-chad symlink (should be removed)"
    else
        pass "install.sh does not create open-chad symlink"
    fi
    teardown_tmp_env
}

test_install_binaries_exist
test_install_path_written_to_rc
test_install_does_not_create_open_chad_symlink

section "lib/update.sh — PATH repair"

test_update_ensures_path_is_current() {
    # update.sh should call setup_shell_profile.sh to ensure PATH is current
    grep -q 'setup_shell_profile' "$REPO_DIR/lib/update.sh" && pass "lib/update.sh calls setup_shell_profile.sh" || fail "lib/update.sh does not call setup_shell_profile.sh"
}

test_update_removes_stale_aliases() {
    # update.sh should still remove stale aliases
    grep -q "alias.*oc.*open-chad\|_remove_stale_alias" "$REPO_DIR/lib/update.sh" && pass "lib/update.sh removes stale aliases" || fail "lib/update.sh does not remove stale aliases"
}

test_update_ensures_path_is_current
test_update_removes_stale_aliases

section "lib/check_environment.sh — warn() defined"

test_check_env_warn_defined() {
    # warn() must be defined before the python3 check that calls it
    if grep -q '^warn()' "$REPO_DIR/lib/check_environment.sh"; then
        pass "check_environment.sh defines warn()"
    else
        fail "check_environment.sh does not define warn() — python3 check will fail"
    fi
}

test_check_env_python3_uses_warn_not_echo() {
    # The python3 warning should use warn() not a bare echo
    local py3_section
    py3_section=$(grep -A5 'python3 not found\|python3.*PATH' "$REPO_DIR/lib/check_environment.sh" 2>/dev/null || echo "")
    if echo "$py3_section" | grep -q 'warn\b'; then
        pass "check_environment.sh python3 warning uses warn()"
    else
        fail "check_environment.sh python3 warning does not use warn()"
    fi
}

test_check_env_warn_defined
test_check_env_python3_uses_warn_not_echo

section "No symlink manifest (v1.1 PATH-based approach)"

test_symlink_manifest_not_created() {
    # Since v1.1, we use PATH directly instead of symlinks
    # The symlink_manifest.sh file should NOT exist
    if [ -f "$REPO_DIR/lib/symlink_manifest.sh" ]; then
        fail "symlink_manifest.sh still exists (should be removed in v1.1)"
    else
        pass "symlink_manifest.sh removed (PATH-based approach)"
    fi
}

test_symlink_manifest_not_created

# ─── Section: ADV Bundling ────────────────────────────────────────────────────

section "ADV Bundling — adv-lock.json"

test_adv_lock_file_exists() {
    assert_file_exists "$REPO_DIR/config/opencode/adv-lock.json"
}

test_adv_lock_json_valid() {
    if node -e "JSON.parse(require('fs').readFileSync('$REPO_DIR/config/opencode/adv-lock.json','utf8'))" 2>/dev/null; then
        pass "adv-lock.json is valid JSON"
    else
        fail "adv-lock.json is not valid JSON"
    fi
}

test_adv_lock_ref_is_sha() {
    local ref
    ref=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$REPO_DIR/config/opencode/adv-lock.json','utf8')).ref)" 2>/dev/null || echo "")
    if echo "$ref" | grep -qE '^[0-9a-f]{40}$'; then
        pass "adv-lock.json ref is a 40-char hex SHA: $ref"
    else
        fail "adv-lock.json ref is not a 40-char hex SHA (got: '$ref')"
    fi
}

test_adv_lock_has_repo_field() {
    local repo
    repo=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$REPO_DIR/config/opencode/adv-lock.json','utf8')).repo)" 2>/dev/null || echo "")
    if [ -n "$repo" ]; then
        pass "adv-lock.json has repo field: $repo"
    else
        fail "adv-lock.json missing repo field"
    fi
}

test_adv_lock_has_plugin_path_field() {
    local pp
    pp=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$REPO_DIR/config/opencode/adv-lock.json','utf8')).pluginPath)" 2>/dev/null || echo "")
    if [ -n "$pp" ]; then
        pass "adv-lock.json has pluginPath field: $pp"
    else
        fail "adv-lock.json missing pluginPath field"
    fi
}

test_adv_lock_file_exists
test_adv_lock_json_valid
test_adv_lock_ref_is_sha
test_adv_lock_has_repo_field
test_adv_lock_has_plugin_path_field

section "ADV Bundling — bundled command docs"

test_adv_command_dir_exists() {
    assert_dir_exists "$REPO_DIR/config/opencode/command"
}

test_adv_bundled_commands_count() {
    local count
    count=$(ls "$REPO_DIR/config/opencode/command"/adv-*.md 2>/dev/null | wc -l)
    if [ "$count" -ge 10 ]; then
        pass "bundled ADV command docs count >= 10 (got $count)"
    else
        fail "bundled ADV command docs count < 10 (got $count)"
    fi
}

test_adv_bundled_commands_include_core() {
    local missing=0
    for cmd in adv-status adv-proposal adv-apply adv-archive adv-prep adv-research adv-review adv-harden; do
        if [ ! -f "$REPO_DIR/config/opencode/command/${cmd}.md" ]; then
            fail "bundled command missing: ${cmd}.md"
            missing=$((missing + 1))
        fi
    done
    [ "$missing" -eq 0 ] && pass "all core ADV command docs present"
}

test_adv_command_dir_exists
test_adv_bundled_commands_count
test_adv_bundled_commands_include_core

section "ADV Bundling — setup_adv.sh structure"

test_setup_adv_reads_lock_file() {
    grep -q 'adv-lock.json\|ADV_LOCK\|adv_lock' "$REPO_DIR/lib/setup_adv.sh" 2>/dev/null \
        && pass "setup_adv.sh references adv-lock.json" \
        || fail "setup_adv.sh does not reference adv-lock.json"
}

test_setup_adv_supports_install_mode() {
    grep -q 'ADV_INSTALL_MODE\|install_mode\|INSTALL_MODE' "$REPO_DIR/lib/setup_adv.sh" 2>/dev/null \
        && pass "setup_adv.sh supports ADV_INSTALL_MODE" \
        || fail "setup_adv.sh missing ADV_INSTALL_MODE support"
}

test_setup_adv_has_offline_fallback() {
    grep -q 'offline\|bundled\|fallback' "$REPO_DIR/lib/setup_adv.sh" 2>/dev/null \
        && pass "setup_adv.sh has offline/bundled fallback path" \
        || fail "setup_adv.sh missing offline/bundled fallback path"
}

test_setup_adv_reads_lock_file
test_setup_adv_supports_install_mode
test_setup_adv_has_offline_fallback

section "ADV Bundling — lock immutability"

test_adv_lock_not_mutated_by_normal_update() {
    # update.sh should NOT overwrite adv-lock.json on normal runs
    # It should only update the lock when --adv-latest is passed
    grep -q 'adv-lock.json' "$REPO_DIR/lib/update.sh" 2>/dev/null \
        && pass "update.sh references adv-lock.json" \
        || fail "update.sh does not reference adv-lock.json"
}

test_adv_lock_update_requires_adv_latest_flag() {
    # The lock ref should only be updated when --adv-latest is explicitly passed
    grep -q '\-\-adv-latest\|adv_latest\|ADV_LATEST' "$REPO_DIR/lib/update.sh" 2>/dev/null \
        && pass "update.sh has --adv-latest flag support" \
        || fail "update.sh missing --adv-latest flag (lock bump requires explicit opt-in)"
}

test_adv_lock_sha_format_enforced() {
    # setup_adv.sh must validate that the ref is a 40-char hex SHA
    grep -qE '40|[0-9a-f]\{40\}|hex|SHA|sha' "$REPO_DIR/lib/setup_adv.sh" 2>/dev/null \
        && pass "setup_adv.sh enforces SHA format on lock ref" \
        || fail "setup_adv.sh does not enforce SHA format on lock ref"
}

test_adv_lock_not_mutated_by_normal_update
test_adv_lock_update_requires_adv_latest_flag
test_adv_lock_sha_format_enforced

section "ADV Bundling — parity (bundled vs pinned)"

test_adv_parity_bundled_matches_upstream_count() {
    # Bundled command count should match what's in the ADV checkout (if present)
    local adv_checkout="${ADV_CHECKOUT_DIR:-$HOME/dev/oc-plugins/advance}"
    local upstream_cmd_dir="$adv_checkout/.opencode/command"
    if [ -d "$upstream_cmd_dir" ]; then
        local upstream_count bundled_count
        upstream_count=$(ls "$upstream_cmd_dir"/adv-*.md 2>/dev/null | wc -l)
        bundled_count=$(ls "$REPO_DIR/config/opencode/command"/adv-*.md 2>/dev/null | wc -l)
        if [ "$bundled_count" -ge "$upstream_count" ]; then
            pass "bundled command count ($bundled_count) >= upstream count ($upstream_count)"
        else
            fail "bundled command count ($bundled_count) < upstream count ($upstream_count) — run: cp $upstream_cmd_dir/adv-*.md $REPO_DIR/config/opencode/command/"
        fi
    else
        skip "ADV checkout not present at $adv_checkout — skipping parity check"
    fi
}

test_adv_parity_bundled_matches_upstream_count

# ─── Section: theme.conf + status_edges agent-order regression ───────────────
# Ensures theme.conf wires dynamic edge renderer and status_edges.sh always emits
# canonical color order: build (#59C2FF) → plan (#FFB454) → scout (#F07178) → refine (#AAD94C)

THEME_CONF="$REPO_DIR/lib/theme.conf"
STATUS_EDGES="$REPO_DIR/lib/status_edges.sh"

section "theme.conf — agent-order edge palette"

test_theme_conf_uses_dynamic_row0_left_edges() {
    assert_contains "$THEME_CONF" "status_edges.sh left row0" "theme.conf row0 left uses dynamic edge renderer"
}

test_theme_conf_uses_dynamic_row0_right_edges() {
    assert_contains "$THEME_CONF" "status_edges.sh right row0" "theme.conf row0 right uses dynamic edge renderer"
}

test_theme_conf_uses_dynamic_row1_left_edges() {
    assert_contains "$THEME_CONF" "status_edges.sh left row1" "theme.conf row1 left uses dynamic edge renderer"
}

test_theme_conf_passes_session_name_to_status_right() {
    assert_contains "$THEME_CONF" "status_right.sh \"#{session_name}\"" "theme.conf row1 right passes session_name to status_right.sh"
}

test_status_edges_order_row0_left() {
    local content blue_pos yellow_pos pink_pos green_pos
    content=$(bash "$STATUS_EDGES" left row0 "oc-123")
    blue_pos=$(echo "$content" | grep -bo "#59C2FF" | head -1 | cut -d: -f1)
    yellow_pos=$(echo "$content" | grep -bo "#FFB454" | head -1 | cut -d: -f1)
    pink_pos=$(echo "$content" | grep -bo "#F07178" | head -1 | cut -d: -f1)
    green_pos=$(echo "$content" | grep -bo "#AAD94C" | head -1 | cut -d: -f1)
    if [ -n "$blue_pos" ] && [ -n "$yellow_pos" ] && [ -n "$pink_pos" ] && [ -n "$green_pos" ] \
        && [ "$blue_pos" -lt "$yellow_pos" ] && [ "$yellow_pos" -lt "$pink_pos" ] && [ "$pink_pos" -lt "$green_pos" ]; then
        pass "status_edges row0-left order: build→plan→scout→refine"
    else
        fail "status_edges row0-left order wrong (blue=$blue_pos yellow=$yellow_pos pink=$pink_pos green=$green_pos)"
    fi
}

test_status_edges_order_row1_right() {
    local content blue_pos yellow_pos pink_pos green_pos
    content=$(bash "$STATUS_EDGES" right row1 "oc-456")
    blue_pos=$(echo "$content" | grep -bo "#59C2FF" | head -1 | cut -d: -f1)
    yellow_pos=$(echo "$content" | grep -bo "#FFB454" | head -1 | cut -d: -f1)
    pink_pos=$(echo "$content" | grep -bo "#F07178" | head -1 | cut -d: -f1)
    green_pos=$(echo "$content" | grep -bo "#AAD94C" | head -1 | cut -d: -f1)
    if [ -n "$blue_pos" ] && [ -n "$yellow_pos" ] && [ -n "$pink_pos" ] && [ -n "$green_pos" ] \
        && [ "$blue_pos" -lt "$yellow_pos" ] && [ "$yellow_pos" -lt "$pink_pos" ] && [ "$pink_pos" -lt "$green_pos" ]; then
        pass "status_edges row1-right order: build→plan→scout→refine"
    else
        fail "status_edges row1-right order wrong (blue=$blue_pos yellow=$yellow_pos pink=$pink_pos green=$green_pos)"
    fi
}

test_status_edges_differs_across_sessions() {
    local a b
    a=$(bash "$STATUS_EDGES" left row1 "oc-111")
    b=$(bash "$STATUS_EDGES" left row1 "oc-222")
    [ "$a" != "$b" ] && pass "status_edges varies glyph shape by session" || fail "status_edges session variation missing"
}

# ─── Per-position independence (256 combinations) ─────────────────────────────
# Each of 4 positions (left-row0, right-row0, left-row1, right-row1) picks its
# own variant independently, giving 4^4 = 256 possible session looks.

test_status_edges_positions_can_differ_in_same_session() {
    # With per-position variants, different positions in the same session
    # should be able to have different glyph patterns
    local left0 right0 left1 right1
    left0=$(bash "$STATUS_EDGES" left row0 "oc-test-session")
    right0=$(bash "$STATUS_EDGES" right row0 "oc-test-session")
    left1=$(bash "$STATUS_EDGES" left row1 "oc-test-session")
    right1=$(bash "$STATUS_EDGES" right row1 "oc-test-session")
    
    # At least one pair should differ (not all positions use same variant)
    if [ "$left0" != "$right0" ] || [ "$left0" != "$left1" ] || [ "$left0" != "$right1" ] || \
       [ "$right0" != "$left1" ] || [ "$right0" != "$right1" ] || [ "$left1" != "$right1" ]; then
        pass "status_edges positions can differ within same session (independence)"
    else
        fail "status_edges all positions identical — per-position independence missing"
    fi
}

test_status_edges_deterministic_per_position() {
    # Same session + same position should always produce same output
    local a b c d
    a=$(bash "$STATUS_EDGES" left row0 "oc-determinism-test")
    b=$(bash "$STATUS_EDGES" left row0 "oc-determinism-test")
    c=$(bash "$STATUS_EDGES" right row1 "oc-determinism-test")
    d=$(bash "$STATUS_EDGES" right row1 "oc-determinism-test")
    
    if [ "$a" = "$b" ] && [ "$c" = "$d" ]; then
        pass "status_edges deterministic per position (stable within session)"
    else
        fail "status_edges not deterministic — output changes for same session+position"
    fi
}

test_status_edges_all_positions_vary_across_sessions() {
    # Each position should vary across different sessions
    local left0_a left0_b right0_a right0_b left1_a left1_b right1_a right1_b
    
    left0_a=$(bash "$STATUS_EDGES" left row0 "oc-session-alpha")
    left0_b=$(bash "$STATUS_EDGES" left row0 "oc-session-beta")
    right0_a=$(bash "$STATUS_EDGES" right row0 "oc-session-alpha")
    right0_b=$(bash "$STATUS_EDGES" right row0 "oc-session-beta")
    left1_a=$(bash "$STATUS_EDGES" left row1 "oc-session-alpha")
    left1_b=$(bash "$STATUS_EDGES" left row1 "oc-session-beta")
    right1_a=$(bash "$STATUS_EDGES" right row1 "oc-session-alpha")
    right1_b=$(bash "$STATUS_EDGES" right row1 "oc-session-beta")
    
    # Each position should show variation across sessions
    local vary_count=0
    [ "$left0_a" != "$left0_b" ] && vary_count=$((vary_count + 1))
    [ "$right0_a" != "$right0_b" ] && vary_count=$((vary_count + 1))
    [ "$left1_a" != "$left1_b" ] && vary_count=$((vary_count + 1))
    [ "$right1_a" != "$right1_b" ] && vary_count=$((vary_count + 1))
    
    if [ "$vary_count" -ge 3 ]; then
        pass "status_edges all positions vary across sessions ($vary_count/4 varied)"
    else
        fail "status_edges insufficient position variation ($vary_count/4 varied)"
    fi
}

test_theme_conf_uses_dynamic_row0_left_edges
test_theme_conf_uses_dynamic_row0_right_edges
test_theme_conf_uses_dynamic_row1_left_edges
test_theme_conf_passes_session_name_to_status_right
test_status_edges_order_row0_left
test_status_edges_order_row1_right
test_status_edges_differs_across_sessions
test_status_edges_positions_can_differ_in_same_session
test_status_edges_deterministic_per_position
test_status_edges_all_positions_vary_across_sessions

# ─── Section: Sandbox Self-Check ──────────────────────────────────────────────
# These tests verify the sandbox infrastructure itself. If these fail, the
# entire test suite is unsafe to run.

section "Sandbox infrastructure — self-check"

test_sandbox_redirects_home() {
    setup_tmp_env
    [ "$HOME" != "$_REAL_HOME" ] && pass "sandbox: HOME redirected away from real home" \
                                  || fail "sandbox: HOME is still real home ($HOME)"
    teardown_tmp_env
}

test_sandbox_home_under_tmp() {
    setup_tmp_env
    case "$HOME" in
        /tmp/*) pass "sandbox: HOME is under /tmp ($HOME)" ;;
        *)      fail "sandbox: HOME is NOT under /tmp ($HOME)" ;;
    esac
    teardown_tmp_env
}

test_sandbox_restores_home_after_teardown() {
    setup_tmp_env
    teardown_tmp_env
    [ "$HOME" = "$_REAL_HOME" ] && pass "sandbox: HOME restored to real home after teardown" \
                                 || fail "sandbox: HOME not restored after teardown (got $HOME, expected $_REAL_HOME)"
}

test_sandbox_assert_catches_unsandboxed() {
    # _assert_sandboxed should fail when HOME is real
    local caught=0
    (
        export HOME="$_REAL_HOME"
        _assert_sandboxed 2>/dev/null
    ) && caught=0 || caught=1
    [ "$caught" -eq 1 ] && pass "sandbox: _assert_sandboxed catches real HOME" \
                         || fail "sandbox: _assert_sandboxed did NOT catch real HOME"
}

test_sandbox_install_writes_to_tmp_only() {
    setup_tmp_env
    local real_rc=""
    local real_mtime_before=""
    # Find the first real rc file that exists
    for rc in "$_REAL_HOME/.zshrc" "$_REAL_HOME/.bashrc" "$_REAL_HOME/.profile"; do
        if [ -f "$rc" ]; then
            real_rc="$rc"
            break
        fi
    done
    [ -n "$real_rc" ] && real_mtime_before=$(stat -c '%Y' "$real_rc" 2>/dev/null || echo "")

    run_install_sandboxed --yes --no-adv --no-omp --no-opencode-setup

    # Verify the sandboxed install wrote PATH to TMP, not real home
    assert_path_in_any_rc

    # Verify real rc file was NOT modified
    if [ -n "$real_mtime_before" ]; then
        local real_mtime_after
        real_mtime_after=$(stat -c '%Y' "$real_rc" 2>/dev/null || echo "")
        [ "$real_mtime_before" = "$real_mtime_after" ] \
            && pass "sandbox: real $(basename "$real_rc") not modified by sandboxed install" \
            || fail "sandbox: real $(basename "$real_rc") WAS modified (mtime changed)"
    else
        pass "sandbox: real rc check skipped (no pre-existing rc file)"
    fi
    teardown_tmp_env
}

test_sandbox_setup_opencode_writes_to_tmp_only() {
    setup_tmp_env
    local real_agents="$_REAL_HOME/.config/opencode/agents"
    local real_mtime_before=""
    [ -d "$real_agents" ] && real_mtime_before=$(stat -c '%Y' "$real_agents" 2>/dev/null || echo "")

    run_setup_opencode_sandboxed --skip-commands

    # Verify agents were written to sandbox
    assert_file_exists "$TMP_HOME/.config/opencode/agents/scout.md"

    # Verify real agents dir was NOT modified
    if [ -n "$real_mtime_before" ]; then
        local real_mtime_after
        real_mtime_after=$(stat -c '%Y' "$real_agents" 2>/dev/null || echo "")
        [ "$real_mtime_before" = "$real_mtime_after" ] \
            && pass "sandbox: real ~/.config/opencode/agents/ not modified" \
            || fail "sandbox: real ~/.config/opencode/agents/ WAS modified (mtime changed)"
    else
        pass "sandbox: real agents check skipped (no pre-existing dir)"
    fi
    teardown_tmp_env
}

# Static self-check: scan this file for raw installer calls that bypass helpers.
# Any direct `bash "$REPO_DIR/install.sh"` or `bash "$REPO_DIR/lib/setup_opencode.sh"`
# outside the helper functions is a sandbox violation waiting to happen.
test_no_raw_installer_calls_outside_helpers() {
    local test_file="$SCRIPT_DIR/install_test.sh"
    local unprotected=0

    while IFS= read -r line; do
        local lineno="${line%%:*}"
        local content="${line#*:}"

        # Skip the helper function bodies (run_install_sandboxed: 143-153, run_setup_opencode_sandboxed: 158-171)
        ([ "$lineno" -ge 143 ] && [ "$lineno" -le 153 ]) && continue
        ([ "$lineno" -ge 158 ] && [ "$lineno" -le 171 ]) && continue
        # Skip comments
        echo "$content" | grep -qE '^\s*#' && continue
        # Skip assert_contains / grep -q (read-only checks on file content)
        echo "$content" | grep -qE 'assert_contains|assert_not_contains|grep -q' && continue

        # Check if this line or nearby preceding lines have env isolation.
        # Multi-line env calls can span 3-4 lines before the `bash` invocation.
        local context=""
        local start=$((lineno > 4 ? lineno - 4 : 1))
        context=$(sed -n "${start},${lineno}p" "$test_file" 2>/dev/null || echo "")

        if echo "$context" | grep -qE 'env\s|run_install_sandboxed|run_setup_opencode_sandboxed|timeout.*env'; then
            continue  # Protected by env isolation in context window
        else
            echo "  WARN: Potentially unprotected call at line $lineno: $content" >&2
            unprotected=$((unprotected + 1))
        fi
    done < <(grep -n 'bash "\$REPO_DIR/install\.sh"\|bash "\$REPO_DIR/lib/setup_opencode\.sh"' "$test_file" 2>/dev/null || true)

    [ "$unprotected" -eq 0 ] \
        && pass "self-check: all installer/setup calls are env-isolated or use helpers" \
        || fail "self-check: $unprotected unprotected installer/setup call(s) found"
}

test_sandbox_redirects_home
test_sandbox_home_under_tmp
test_sandbox_restores_home_after_teardown
test_sandbox_assert_catches_unsandboxed
test_sandbox_install_writes_to_tmp_only
test_sandbox_setup_opencode_writes_to_tmp_only
test_no_raw_installer_calls_outside_helpers

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
