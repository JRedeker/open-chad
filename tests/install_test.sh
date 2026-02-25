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
    mkdir -p "$TMP_INSTALL_DIR"
    # Copy repo into temp install dir to simulate fresh checkout
    cp -r "$REPO_DIR"/. "$TMP_INSTALL_DIR/"
    export HOME="$TMP_HOME"
}

teardown_tmp_env() {
    rm -rf "$TMP_DIR"
    unset TMP_DIR TMP_HOME TMP_INSTALL_DIR
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

test_setup_adv_skips_gracefully_without_pnpm

# ─── Section 6: install.sh flag parsing ───────────────────────────────────────

section "install.sh — flag parsing"

test_install_accepts_no_adv_flag() {
    setup_tmp_env
    # Pass all --no-* flags to avoid sub-script execution in test environment
    local output
    output=$(HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup 2>&1) || true
    # Should not error on unknown-flag
    echo "$output" | grep -qi "unknown.*--no-adv\|invalid.*--no-adv\|illegal.*--no-adv" && fail "--no-adv flag caused error" || pass "--no-adv flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_omp_flag() {
    setup_tmp_env
    local output
    output=$(HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup 2>&1) || true
    echo "$output" | grep -qi "unknown.*--no-omp\|invalid.*--no-omp\|illegal.*--no-omp" && fail "--no-omp flag caused error" || pass "--no-omp flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_opencode_setup_flag() {
    setup_tmp_env
    local output
    output=$(HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --no-adv --no-omp --no-opencode-setup 2>&1) || true
    echo "$output" | grep -qi "unknown\|invalid\|error.*flag\|illegal" && fail "--no-opencode-setup flag caused error" || pass "--no-opencode-setup flag parsed without error"
    teardown_tmp_env
}

test_install_accepts_no_adv_flag
test_install_accepts_no_omp_flag
test_install_accepts_no_opencode_setup_flag

# ─── Section 7: install.sh idempotency ────────────────────────────────────────

section "install.sh — idempotency (tmux theme + symlink)"

test_install_symlink_idempotent() {
    setup_tmp_env
    # Run install twice with all sub-steps skipped (isolates tmux+symlink behavior)
    HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --yes --no-adv --no-omp --no-opencode-setup --no-env-check > /dev/null 2>&1 || true
    HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --yes --no-adv --no-omp --no-opencode-setup --no-env-check > /dev/null 2>&1 || true
    assert_symlink "$TMP_HOME/.local/bin/open-chad"
    teardown_tmp_env
}

test_install_tmux_theme_not_duplicated() {
    setup_tmp_env
    # Create existing tmux.conf
    echo "# existing config" > "$TMP_HOME/.tmux.conf"

    HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --yes --no-adv --no-omp --no-opencode-setup --no-env-check > /dev/null 2>&1 || true
    HOME="$TMP_HOME" bash "$REPO_DIR/install.sh" --yes --no-adv --no-omp --no-opencode-setup --no-env-check > /dev/null 2>&1 || true

    # Theme source should appear exactly once
    local count
    count=$(grep -c "OPEN-CHAD THEME" "$TMP_HOME/.tmux.conf" 2>/dev/null || echo 0)
    [ "$count" -le 1 ] && pass "tmux theme not duplicated (count=$count)" || fail "tmux theme duplicated (count=$count)"
    teardown_tmp_env
}

test_install_symlink_idempotent
test_install_tmux_theme_not_duplicated

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
    XDG_RUNTIME_DIR="$TMP_DIR/runtime" \
        bash "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null
    assert_dir_exists "$fake_cache"
    assert_perms_700 "$fake_cache"
    teardown_tmp_env
}

test_opencode_env_fallback_without_xdg() {
    setup_tmp_env
    # Unset XDG_RUNTIME_DIR to trigger fallback path
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
    # Source the env file and verify OPEN_CHAD_CACHE_DIR is set
    local exported_val
    exported_val=$(XDG_RUNTIME_DIR="$fake_runtime" bash -c \
        'source "$1" && echo "$OPEN_CHAD_CACHE_DIR"' _ "$REPO_DIR/lib/opencode_env.sh" 2>/dev/null)
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

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
