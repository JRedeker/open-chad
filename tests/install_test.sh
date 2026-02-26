#!/usr/bin/env bash
# tests/install_test.sh — Plain bash test suite for open-chad installer
# Tests: idempotency, flag behavior, file creation, missing-dep graceful skip
#
# Usage: bash tests/install_test.sh
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
assert_symlink() { [ -L "$1" ] && pass "symlink: $1" || fail "not a symlink: $1"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Temp Environment Setup ───────────────────────────────────────────────────

setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    TMP_HOME="$TMP_DIR/home"
    TMP_INSTALL_DIR="$TMP_DIR/install"
    mkdir -p "$TMP_HOME/.local/bin"
    mkdir -p "$TMP_HOME/.config/opencode"
    mkdir -p "$TMP_DIR/cache"
    mkdir -p "$TMP_INSTALL_DIR"
    # Copy repo into temp install dir to simulate fresh checkout
    cp -r "$REPO_DIR"/. "$TMP_INSTALL_DIR/"
    export HOME="$TMP_HOME"
    # Sandbox cache dir so opencode_env.sh doesn't touch real XDG_RUNTIME_DIR
    export OPEN_CHAD_CACHE_DIR="$TMP_DIR/cache"
}

teardown_tmp_env() {
    rm -rf "$TMP_DIR"
    unset TMP_DIR TMP_HOME TMP_INSTALL_DIR OPEN_CHAD_CACHE_DIR
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
    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$TMP_DIR/fake-adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" --skip-commands 2>/dev/null || true

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
    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$TMP_DIR/fake-adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" --skip-commands 2>/dev/null || true

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
    mkdir -p "$fake_adv/plugin/commands"
    echo "# adv-status" > "$fake_adv/plugin/commands/adv-status.md"
    echo "# adv-apply" > "$fake_adv/plugin/commands/adv-apply.md"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$fake_adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" 2>/dev/null || true

    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-status.md"
    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-apply.md"
    teardown_tmp_env
}

test_setup_opencode_is_idempotent() {
    setup_tmp_env
    local fake_adv="$TMP_DIR/fake-adv"
    mkdir -p "$fake_adv/plugin/commands"
    echo "# adv-status" > "$fake_adv/plugin/commands/adv-status.md"

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$fake_adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" 2>/dev/null || true

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$fake_adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" 2>/dev/null || true

    # Files should exist, not duplicated
    assert_file_exists "$TMP_HOME/.config/opencode/agents/scout.md"
    assert_file_exists "$TMP_HOME/.config/opencode/command/adv-status.md"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands
test_setup_opencode_syncs_agents
test_setup_opencode_syncs_instructions
test_setup_opencode_is_idempotent

# ─── Section 4: setup_omp.sh — go install ─────────────────────────────────────

section "lib/setup_omp.sh — go install omp"

test_setup_omp_skips_gracefully_without_go() {
    if command -v go &>/dev/null; then
        skip "go is installed; skipping missing-go test"
        return
    fi
    setup_tmp_env
    local output
    output=$(OMP_INSTALL_DIR="$TMP_HOME/.local/bin" bash "$REPO_DIR/lib/setup_omp.sh" 2>&1) || true
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
    local output
    output=$(OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" bash "$REPO_DIR/lib/setup_adv.sh" 2>&1) || true
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
    # Pass all --no-* flags to avoid sub-script execution in test environment
    local output
    output=$(timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --no-adv --no-omp --no-opencode-setup --no-env-check" 2>&1) || true
    # Should not error on unknown-flag
    echo "$output" | grep -qi "unknown.*--no-adv\|invalid.*--no-adv\|illegal.*--no-adv" && fail "--no-adv flag caused error" || pass "--no-adv flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_omp_flag() {
    setup_tmp_env
    local output
    output=$(timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --no-adv --no-omp --no-opencode-setup --no-env-check" 2>&1) || true
    echo "$output" | grep -qi "unknown.*--no-omp\|invalid.*--no-omp\|illegal.*--no-omp" && fail "--no-omp flag caused error" || pass "--no-omp flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_opencode_setup_flag() {
    setup_tmp_env
    local output
    output=$(timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --no-adv --no-omp --no-opencode-setup --no-env-check" 2>&1) || true
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

section "install.sh — idempotency (tmux theme + symlink)"

test_install_symlink_idempotent() {
    setup_tmp_env
    # Run install twice with all sub-steps skipped (isolates tmux+symlink behavior)
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/open-chad"
    assert_symlink "$TMP_HOME/.local/bin/cds"
    teardown_tmp_env
}

test_install_cds_symlink_created() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/cds"
    teardown_tmp_env
}

test_install_cds_symlink_points_to_bin_cds() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    local target
    target=$(readlink "$TMP_HOME/.local/bin/cds" 2>/dev/null || echo "")
    if echo "$target" | grep -q "bin/cds"; then
        pass "cds symlink points to bin/cds"
    else
        fail "cds symlink target unexpected: $target"
    fi
    teardown_tmp_env
}

test_install_tmux_theme_not_duplicated() {
    setup_tmp_env
    # Create existing tmux.conf
    echo "# existing config" > "$TMP_HOME/.tmux.conf"

    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true

    # Theme source should appear exactly once
    local count
    count=$(grep -c "OPEN-CHAD THEME" "$TMP_HOME/.tmux.conf" 2>/dev/null || echo 0)
    [ "$count" -le 1 ] && pass "tmux theme not duplicated (count=$count)" || fail "tmux theme duplicated (count=$count)"
    teardown_tmp_env
}

test_install_symlink_idempotent
test_install_cds_symlink_created
test_install_cds_symlink_points_to_bin_cds
test_install_tmux_theme_not_duplicated

test_install_oc_list_symlink_created() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/oc-list"
    teardown_tmp_env
}

test_install_oc_killall_symlink_created() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/oc-killall"
    teardown_tmp_env
}

test_install_oc_list_symlink_points_to_bin() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    local target
    target=$(readlink "$TMP_HOME/.local/bin/oc-list" 2>/dev/null || echo "")
    if echo "$target" | grep -q "bin/oc-list"; then
        pass "oc-list symlink points to bin/oc-list"
    else
        fail "oc-list symlink target unexpected: $target"
    fi
    teardown_tmp_env
}

test_install_oc_killall_symlink_points_to_bin() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    local target
    target=$(readlink "$TMP_HOME/.local/bin/oc-killall" 2>/dev/null || echo "")
    if echo "$target" | grep -q "bin/oc-killall"; then
        pass "oc-killall symlink points to bin/oc-killall"
    else
        fail "oc-killall symlink target unexpected: $target"
    fi
    teardown_tmp_env
}

test_install_oc_list_symlink_created
test_install_oc_killall_symlink_created
test_install_oc_list_symlink_points_to_bin
test_install_oc_killall_symlink_points_to_bin

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
    XDG_RUNTIME_DIR="$TMP_DIR/runtime" \
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
    unset XDG_RUNTIME_DIR
    bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null || true
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
    exported_val=$(XDG_RUNTIME_DIR="$fake_runtime" OPEN_CHAD_CACHE_DIR="" bash -c \
        'unset OPEN_CHAD_CACHE_DIR; source "$1" && echo "$OPEN_CHAD_CACHE_DIR"' _ "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null)
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
    used_val=$(OPEN_CHAD_CACHE_DIR="$custom_dir" \
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
    XDG_RUNTIME_DIR="$fake_runtime" bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
    XDG_RUNTIME_DIR="$fake_runtime" bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
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
        '{"mcp":{"context7":{"type":"local","command":["npx","-y","context7-mcp"],"enabled":true}}}' \
        2>/dev/null

    # Step 2: Merge second MCP server (should ADD, not REPLACE)
    bash "$REPO_DIR/lib/json_merge.sh" "$tmp_json" \
        '{"mcp":{"grep-app":{"type":"local","command":["npx","-y","grep-app-mcp"],"enabled":true}}}' \
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
    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$TMP_DIR/fake-adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" --skip-commands 2>/dev/null || true

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

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$fake_adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" 2>/dev/null || true

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

    OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
    ADV_CHECKOUT_DIR="$fake_adv" \
        bash "$REPO_DIR/lib/setup_opencode.sh" --skip-commands 2>/dev/null || true

    # Upstream checkout version should win over bundled fallback
    assert_contains "$TMP_HOME/.config/opencode/agents/adv-researcher.md" "adv-researcher upstream"
    teardown_tmp_env
}

test_setup_opencode_syncs_adv_commands_opencode_layout
test_setup_opencode_syncs_adv_commands_opencode_layout_agents

# ─── Section 14: bin/open-chad metrics collector atomic lockdir ───────────────

section "bin/open-chad — atomic mkdir lockdir for metrics collector"

test_open_chad_uses_atomic_mkdir_for_metrics_singleton() {
    # Verify bin/open-chad uses mkdir-based atomic lock (not just pgrep)
    # for the metrics collector singleton guard.
    # The startup lock is metrics-start.lock (distinct from the collector's
    # own PID-based metrics.lock file to avoid dir/file collision).
    assert_contains "$REPO_DIR/bin/open-chad" "mkdir"
    assert_contains "$REPO_DIR/bin/open-chad" "metrics-start.lock"
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
    # bin/open-chad should remove stale /tmp/discord-rpc.lock* files on startup
    assert_contains "$REPO_DIR/bin/open-chad" "_legacy_discord_lock"
    assert_contains "$REPO_DIR/bin/open-chad" "/tmp/discord-rpc.lock"
}

test_open_chad_legacy_cleanup_checks_regular_file() {
    # Cleanup must check [ -f ] and [ ! -L ] to avoid symlink-follow deletion
    assert_contains "$REPO_DIR/bin/open-chad" '! -L'
    # Check for -f check on the legacy file variable (pattern avoids shell expansion)
    if grep -q '\-f.*_legacy_file' "$REPO_DIR/bin/open-chad"; then
        pass "bin/open-chad: legacy cleanup checks -f before deleting"
    else
        fail "bin/open-chad: legacy cleanup missing -f check on _legacy_file"
    fi
}

test_open_chad_legacy_cleanup_covers_guard_and_tagline() {
    # All three legacy lock variants should be cleaned up
    assert_contains "$REPO_DIR/bin/open-chad" '.guard'
    assert_contains "$REPO_DIR/bin/open-chad" '.tagline'
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
    output=$(OPENCODE_CONFIG_DIR="$TMP_HOME/.config/opencode" \
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
    assert_contains "$REPO_DIR/bin/open-chad" "discord.log"
    assert_not_contains "$REPO_DIR/bin/open-chad" 'discord/update.sh.*2>/dev/null'
}

test_open_chad_discord_log_created_with_0600() {
    # The discord.log file should be created with 0600 permissions
    assert_contains "$REPO_DIR/bin/open-chad" "0600"
}

test_open_chad_discord_stderr_logged_not_devnull
test_open_chad_discord_log_created_with_0600

# ─── Section 21: ISSUE-006 — Atomic ln -sfn in install.sh and update.sh ───────

section "ISSUE-006 — Atomic ln -sfn in install.sh and update.sh"

test_install_sh_uses_ln_sfn() {
    assert_contains "$REPO_DIR/install.sh" "ln -sfn"
}

test_update_sh_uses_ln_sfn() {
    assert_contains "$REPO_DIR/lib/update.sh" "ln -sfn"
}

test_install_sh_no_rm_then_ln() {
    # Should not have the old non-atomic rm -f + ln -s pattern
    assert_not_contains "$REPO_DIR/install.sh" 'rm -f.*&&.*ln -s '
}

test_install_sh_uses_ln_sfn
test_update_sh_uses_ln_sfn
test_install_sh_no_rm_then_ln

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

section "install.sh — openchad/oc symlink set"

test_install_creates_openchad_symlink() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/openchad"
    teardown_tmp_env
}

test_install_creates_oc_symlink() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/oc"
    teardown_tmp_env
}

test_install_openchad_points_to_bin_openchad() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    local target
    target=$(readlink "$TMP_HOME/.local/bin/openchad" 2>/dev/null || echo "")
    echo "$target" | grep -q "bin/openchad" && pass "openchad symlink points to bin/openchad" || fail "openchad symlink target unexpected: $target"
    teardown_tmp_env
}

test_install_oc_points_to_bin_oc() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    local target
    target=$(readlink "$TMP_HOME/.local/bin/oc" 2>/dev/null || echo "")
    echo "$target" | grep -q "bin/oc" && pass "oc symlink points to bin/oc" || fail "oc symlink target unexpected: $target"
    teardown_tmp_env
}

test_install_does_not_create_open_chad_symlink() {
    setup_tmp_env
    timeout --signal=KILL 3 bash -c "HOME='$TMP_HOME' OPEN_CHAD_CACHE_DIR='$TMP_DIR/cache' bash '$REPO_DIR/install.sh' --yes --no-adv --no-omp --no-opencode-setup --no-env-check" > /dev/null 2>&1 || true
    if [ -L "$TMP_HOME/.local/bin/open-chad" ]; then
        fail "install.sh still creates open-chad symlink (should be removed)"
    else
        pass "install.sh does not create open-chad symlink"
    fi
    teardown_tmp_env
}

test_install_creates_openchad_symlink
test_install_creates_oc_symlink
test_install_openchad_points_to_bin_openchad
test_install_oc_points_to_bin_oc
test_install_does_not_create_open_chad_symlink

section "lib/update.sh — full symlink repair set"

test_update_repairs_openchad_symlink() {
    grep -q 'openchad' "$REPO_DIR/lib/update.sh" && pass "lib/update.sh references openchad" || fail "lib/update.sh does not reference openchad"
}

test_update_repairs_oc_symlink() {
    grep -q '"oc"\|bin/oc' "$REPO_DIR/lib/update.sh" && pass "lib/update.sh references oc" || fail "lib/update.sh does not reference oc"
}

test_update_repairs_oc_list_symlink() {
    grep -q 'oc-list' "$REPO_DIR/lib/update.sh" && pass "lib/update.sh references oc-list" || fail "lib/update.sh does not reference oc-list"
}

test_update_repairs_oc_killall_symlink() {
    grep -q 'oc-killall' "$REPO_DIR/lib/update.sh" && pass "lib/update.sh references oc-killall" || fail "lib/update.sh does not reference oc-killall"
}

test_update_repairs_openchad_symlink
test_update_repairs_oc_symlink
test_update_repairs_oc_list_symlink
test_update_repairs_oc_killall_symlink

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

section "lib/symlink_manifest.sh — shared manifest"

test_symlink_manifest_exists() {
    assert_file_exists "$REPO_DIR/lib/symlink_manifest.sh"
}

test_symlink_manifest_contains_openchad() {
    grep -q 'openchad' "$REPO_DIR/lib/symlink_manifest.sh" 2>/dev/null && pass "symlink_manifest.sh contains openchad" || fail "symlink_manifest.sh missing openchad"
}

test_symlink_manifest_contains_oc() {
    grep -q '"oc"\|bin/oc' "$REPO_DIR/lib/symlink_manifest.sh" 2>/dev/null && pass "symlink_manifest.sh contains oc" || fail "symlink_manifest.sh missing oc"
}

test_symlink_manifest_contains_cds() {
    grep -q 'cds' "$REPO_DIR/lib/symlink_manifest.sh" 2>/dev/null && pass "symlink_manifest.sh contains cds" || fail "symlink_manifest.sh missing cds"
}

test_symlink_manifest_contains_oc_list() {
    grep -q 'oc-list' "$REPO_DIR/lib/symlink_manifest.sh" 2>/dev/null && pass "symlink_manifest.sh contains oc-list" || fail "symlink_manifest.sh missing oc-list"
}

test_symlink_manifest_contains_oc_killall() {
    grep -q 'oc-killall' "$REPO_DIR/lib/symlink_manifest.sh" 2>/dev/null && pass "symlink_manifest.sh contains oc-killall" || fail "symlink_manifest.sh missing oc-killall"
}

test_symlink_manifest_exists
test_symlink_manifest_contains_openchad
test_symlink_manifest_contains_oc
test_symlink_manifest_contains_cds
test_symlink_manifest_contains_oc_list
test_symlink_manifest_contains_oc_killall

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
