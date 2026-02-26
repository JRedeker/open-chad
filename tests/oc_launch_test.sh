#!/usr/bin/env bash
# tests/oc_launch_test.sh — Unit tests for bin/oc project-name resolution
#
# Tests the `oc <project>` shorthand that resolves bare project names to
# ~/dev/<project> or ~/dev/*/<project> before forwarding to openchad.
#
# Resolution precedence (highest to lowest):
#   1. openchad subcommands (update, doctor, version, uninstall, metrics,
#      changelog, discord) — always forwarded unchanged
#   2. Explicit path prefixes (./, ../, /, ~) — forwarded unchanged
#   3. Exact ~/dev/<token> match — rewritten to absolute path
#   4. Single ~/dev/*/<token> match — rewritten with stderr notice
#   5. Multiple ~/dev/*/<token> matches — exit 1 + disambiguation list
#   6. No match — forwarded unchanged (openchad handles the error)
#
# Usage: bash tests/oc_launch_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OC_BIN="$REPO_DIR/bin/oc"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq()           { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains()     { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (pattern '$2' not found in output)"; }
assert_not_contains() { echo "$1" | grep -q "$2" && fail "$3 (pattern '$2' unexpectedly found)" || pass "$3"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Test Environment Setup ───────────────────────────────────────────────────
#
# bin/oc resolves openchad via SCRIPT_DIR (the directory containing bin/oc),
# not via PATH. So we create a temp bin/ directory containing:
#   - a symlink to the real bin/oc
#   - a fake openchad that records its argv
#
# This ensures SCRIPT_DIR/openchad points to our fake binary.

TMP_DIR=""

setup_tmp_env() {
    TMP_DIR=$(mktemp -d)
    export HOME="$TMP_DIR/home"
    mkdir -p "$HOME"

    # Create a temp bin dir with fake openchad alongside a copy of bin/oc
    local fake_bin="$TMP_DIR/bin"
    mkdir -p "$fake_bin"

    # Copy bin/oc into the temp bin dir (so SCRIPT_DIR = $fake_bin)
    cp "$OC_BIN" "$fake_bin/oc"
    chmod +x "$fake_bin/oc"

    # Create fake openchad that records argv to a capture file
    cat > "$fake_bin/openchad" <<'FAKE'
#!/usr/bin/env bash
# Fake openchad — records argv to capture file (one arg per line)
printf '%s\n' "$@" > "${OPENCHAD_CAPTURE_FILE:-/dev/null}"
exit 0
FAKE
    chmod +x "$fake_bin/openchad"

    export _OC_TEST_BIN="$fake_bin/oc"
    export _OC_CAPTURE_FILE="$TMP_DIR/argv_capture"
}

teardown_tmp_env() {
    [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    TMP_DIR=""
    unset _OC_TEST_BIN _OC_CAPTURE_FILE 2>/dev/null || true
}

# Run oc with the test harness.
# Usage: _run_oc [oc args...]
# Stdout/stderr available via command substitution at call site.
# Exit code returned normally.
_run_oc() {
    OPENCHAD_CAPTURE_FILE="$_OC_CAPTURE_FILE" \
        bash "$_OC_TEST_BIN" "$@"
}

# Read first line of capture file (first forwarded arg)
_first_arg() { head -1 "$_OC_CAPTURE_FILE" 2>/dev/null || echo ""; }

# Read nth line of capture file
_nth_arg() { sed -n "${1}p" "$_OC_CAPTURE_FILE" 2>/dev/null || echo ""; }

# Read all captured args
_all_args() { cat "$_OC_CAPTURE_FILE" 2>/dev/null || echo ""; }

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 1: File properties
# ═══════════════════════════════════════════════════════════════════════════════

section "bin/oc — file properties"

[ -f "$OC_BIN" ] && pass "bin/oc exists" || fail "bin/oc missing"
[ -x "$OC_BIN" ] && pass "bin/oc is executable" || fail "bin/oc not executable"
bash -n "$OC_BIN" 2>/dev/null && pass "bin/oc syntax OK" || fail "bin/oc syntax error"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 2: Subcommand precedence — subcommands must never be rewritten
# ═══════════════════════════════════════════════════════════════════════════════

section "subcommand precedence — subcommands forwarded unchanged"

_test_subcommand_passthrough() {
    local subcmd="$1"
    setup_tmp_env
    # Create ~/dev/<subcmd> to prove directory existence doesn't hijack routing
    mkdir -p "$HOME/dev/$subcmd"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "$subcmd" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$subcmd" "oc $subcmd forwarded as subcommand (not rewritten to path)"
    teardown_tmp_env
}

for _sc in update doctor version uninstall metrics changelog discord; do
    _test_subcommand_passthrough "$_sc"
done

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 3: Explicit path passthrough — paths must never be rewritten
# ═══════════════════════════════════════════════════════════════════════════════

section "explicit path passthrough — paths forwarded unchanged"

_test_explicit_path_passthrough() {
    local path_arg="$1"
    local label="$2"
    setup_tmp_env
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "$path_arg" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$path_arg" "oc '$path_arg' forwarded unchanged ($label)"
    teardown_tmp_env
}

_test_explicit_path_passthrough "./myproject"  "relative ./"
_test_explicit_path_passthrough "../myproject" "relative ../"
_test_explicit_path_passthrough "/abs/path"    "absolute /"
_test_explicit_path_passthrough "~/dev/myproj" "tilde-prefixed"

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 4: Exact top-level match — ~/dev/<token> exists
# ═══════════════════════════════════════════════════════════════════════════════

section "exact top-level match — ~/dev/<token>"

test_exact_toplevel_match() {
    setup_tmp_env
    mkdir -p "$HOME/dev/myproject"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "myproject" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$HOME/dev/myproject" \
        "oc myproject resolves to ~/dev/myproject"
    teardown_tmp_env
}

test_exact_toplevel_match_preserves_remaining_argv() {
    setup_tmp_env
    mkdir -p "$HOME/dev/myproject"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "myproject" "--no-anim" >/dev/null 2>&1 || true
    local first second
    first=$(_first_arg)
    second=$(_nth_arg 2)
    assert_eq "$first"  "$HOME/dev/myproject" \
        "oc myproject --no-anim: first arg resolved"
    assert_eq "$second" "--no-anim" \
        "oc myproject --no-anim: --no-anim preserved as second arg"
    teardown_tmp_env
}

test_exact_toplevel_match
test_exact_toplevel_match_preserves_remaining_argv

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 5: Single nested match — ~/dev/*/<token> (one level deep)
# ═══════════════════════════════════════════════════════════════════════════════

section "single nested match — ~/dev/*/<token>"

test_single_nested_match_resolves() {
    setup_tmp_env
    # No top-level match; one nested match
    mkdir -p "$HOME/dev/oc-plugins/morph-fast-apply"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "morph-fast-apply" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$HOME/dev/oc-plugins/morph-fast-apply" \
        "oc morph-fast-apply resolves to nested ~/dev/oc-plugins/morph-fast-apply"
    teardown_tmp_env
}

test_single_nested_match_prints_notice_to_stderr() {
    setup_tmp_env
    mkdir -p "$HOME/dev/oc-plugins/morph-fast-apply"
    rm -f "$_OC_CAPTURE_FILE"
    local stderr_out
    stderr_out=$(_run_oc "morph-fast-apply" 2>&1 >/dev/null) || true
    assert_contains "$stderr_out" "morph-fast-apply" \
        "oc morph-fast-apply prints resolution notice to stderr"
    teardown_tmp_env
}

test_single_nested_match_preserves_remaining_argv() {
    setup_tmp_env
    mkdir -p "$HOME/dev/oc-plugins/morph-fast-apply"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "morph-fast-apply" "--no-anim" >/dev/null 2>&1 || true
    local second
    second=$(_nth_arg 2)
    assert_eq "$second" "--no-anim" \
        "oc morph-fast-apply --no-anim: remaining argv preserved after nested resolve"
    teardown_tmp_env
}

test_single_nested_match_resolves
test_single_nested_match_prints_notice_to_stderr
test_single_nested_match_preserves_remaining_argv

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 6: Ambiguous nested matches — multiple ~/dev/*/<token>
# ═══════════════════════════════════════════════════════════════════════════════

section "ambiguous nested matches — exit 1 + disambiguation"

test_ambiguous_nested_exits_nonzero() {
    setup_tmp_env
    mkdir -p "$HOME/dev/group-a/shared"
    mkdir -p "$HOME/dev/group-b/shared"
    rm -f "$_OC_CAPTURE_FILE"
    local rc=0
    _run_oc "shared" >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ] && pass "oc shared exits non-zero on ambiguous match" \
                     || fail "oc shared should exit non-zero on ambiguous match (got 0)"
    teardown_tmp_env
}

test_ambiguous_nested_prints_disambiguation() {
    setup_tmp_env
    mkdir -p "$HOME/dev/group-a/shared"
    mkdir -p "$HOME/dev/group-b/shared"
    rm -f "$_OC_CAPTURE_FILE"
    local stderr_out
    stderr_out=$(_run_oc "shared" 2>&1 >/dev/null) || true
    assert_contains "$stderr_out" "group-a" \
        "oc shared disambiguation lists group-a/shared"
    assert_contains "$stderr_out" "group-b" \
        "oc shared disambiguation lists group-b/shared"
    teardown_tmp_env
}

test_ambiguous_nested_does_not_forward_to_openchad() {
    setup_tmp_env
    mkdir -p "$HOME/dev/group-a/shared"
    mkdir -p "$HOME/dev/group-b/shared"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "shared" >/dev/null 2>&1 || true
    local forwarded
    forwarded=$(_all_args)
    assert_eq "$forwarded" "" \
        "oc shared does not forward to openchad on ambiguous match"
    teardown_tmp_env
}

test_ambiguous_nested_exits_nonzero
test_ambiguous_nested_prints_disambiguation
test_ambiguous_nested_does_not_forward_to_openchad

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 7: No match — unknown token forwarded unchanged
# ═══════════════════════════════════════════════════════════════════════════════

section "no match — unknown token forwarded unchanged"

test_unknown_token_forwarded_unchanged() {
    setup_tmp_env
    mkdir -p "$HOME/dev"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "nonexistent-project" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "nonexistent-project" \
        "oc nonexistent-project forwarded unchanged when no ~/dev match"
    teardown_tmp_env
}

test_no_dev_dir_forwarded_unchanged() {
    setup_tmp_env
    # ~/dev doesn't exist at all
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "myproject" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "myproject" \
        "oc myproject forwarded unchanged when ~/dev does not exist"
    teardown_tmp_env
}

test_unknown_token_forwarded_unchanged
test_no_dev_dir_forwarded_unchanged

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 8: Top-level takes priority over nested
# ═══════════════════════════════════════════════════════════════════════════════

section "top-level priority over nested"

test_toplevel_wins_over_nested() {
    setup_tmp_env
    # Both ~/dev/x and ~/dev/group/x exist — top-level must win
    mkdir -p "$HOME/dev/x"
    mkdir -p "$HOME/dev/group/x"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "x" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$HOME/dev/x" \
        "oc x resolves to ~/dev/x (top-level) not ~/dev/group/x (nested)"
    teardown_tmp_env
}

test_toplevel_wins_over_nested

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 9: No-args passthrough
# ═══════════════════════════════════════════════════════════════════════════════

section "no-args passthrough"

test_no_args_forwarded() {
    setup_tmp_env
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc >/dev/null 2>&1 || true
    local forwarded
    forwarded=$(_all_args)
    assert_eq "$forwarded" "" "oc with no args forwards no args to openchad"
    teardown_tmp_env
}

test_no_args_forwarded

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 10: Edge cases — robustness
# ═══════════════════════════════════════════════════════════════════════════════

section "edge cases — robustness"

test_file_not_directory_not_resolved() {
    setup_tmp_env
    mkdir -p "$HOME/dev"
    touch "$HOME/dev/myfile"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "myfile" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "myfile" \
        "oc myfile not resolved when ~/dev/myfile is a regular file (not dir)"
    teardown_tmp_env
}

test_options_before_project_not_resolved() {
    setup_tmp_env
    mkdir -p "$HOME/dev/myproject"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "--no-anim" "myproject" >/dev/null 2>&1 || true
    local first second
    first=$(_first_arg)
    second=$(_nth_arg 2)
    assert_eq "$first"  "--no-anim" \
        "oc --no-anim myproject: --no-anim forwarded as first arg"
    assert_eq "$second" "$HOME/dev/myproject" \
        "oc --no-anim myproject: myproject resolved as second arg"
    teardown_tmp_env
}

test_file_not_directory_not_resolved
test_options_before_project_not_resolved

# ═══════════════════════════════════════════════════════════════════════════════
# SECTION 11: Failure-path coverage — glob chars, whitespace, symlinks
# ═══════════════════════════════════════════════════════════════════════════════

section "failure-path coverage — glob chars, whitespace, symlinks"

test_glob_chars_in_token_not_expanded() {
    setup_tmp_env
    mkdir -p "$HOME/dev"
    # A token with glob chars should not expand and should be forwarded unchanged
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "my*project" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "my*project" \
        "oc 'my*project' forwarded unchanged (glob chars not expanded)"
    teardown_tmp_env
}

test_project_name_with_spaces_in_argv() {
    setup_tmp_env
    # Project name with spaces (passed as single quoted arg)
    mkdir -p "$HOME/dev/my project"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "my project" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$HOME/dev/my project" \
        "oc 'my project' resolves correctly when ~/dev/my project exists"
    teardown_tmp_env
}

test_symlink_to_directory_resolves() {
    setup_tmp_env
    # A symlink pointing to a directory should resolve (it's a valid project dir)
    mkdir -p "$HOME/dev/real-project"
    ln -s "$HOME/dev/real-project" "$HOME/dev/alias-project"
    rm -f "$_OC_CAPTURE_FILE"
    _run_oc "alias-project" >/dev/null 2>&1 || true
    local first
    first=$(_first_arg)
    assert_eq "$first" "$HOME/dev/alias-project" \
        "oc alias-project resolves when ~/dev/alias-project is a symlink to a dir"
    teardown_tmp_env
}

test_empty_dev_dir_no_crash() {
    setup_tmp_env
    # ~/dev exists but is empty — should not crash, token forwarded unchanged
    mkdir -p "$HOME/dev"
    rm -f "$_OC_CAPTURE_FILE"
    local rc=0
    _run_oc "myproject" >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 1 ] && pass "oc myproject does not crash when ~/dev is empty" \
                     || fail "oc myproject crashed (exit 1) when ~/dev is empty"
    local first
    first=$(_first_arg)
    assert_eq "$first" "myproject" \
        "oc myproject forwarded unchanged when ~/dev is empty"
    teardown_tmp_env
}

test_glob_chars_in_token_not_expanded
test_project_name_with_spaces_in_argv
test_symlink_to_directory_resolves
test_empty_dev_dir_no_crash

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo "══════════════════════════════════════════════"
echo "  oc_launch_test.sh results"
echo "══════════════════════════════════════════════"
echo "  Passed:  $TESTS_PASSED"
echo "  Failed:  $TESTS_FAILED"
echo "══════════════════════════════════════════════"

exit "$TESTS_FAILED"
