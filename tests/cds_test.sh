#!/usr/bin/env bash
# tests/cds_test.sh — Unit tests for bin/cds
# Tests: default date, explicit date, directory creation, launch target,
#        help flag, missing openchad fallback, idempotent dir creation
#
# Usage: bash tests/cds_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CDS_BIN="$REPO_DIR/bin/cds"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (pattern '$2' not found in '$1')"; }
assert_file_exists() { [ -f "$1" ] && pass "file exists: $1" || fail "file missing: $1"; }
assert_dir_exists()  { [ -d "$1" ] && pass "dir exists: $1" || fail "dir missing: $1"; }
assert_executable()  { [ -x "$1" ] && pass "executable: $1" || fail "not executable: $1"; }
assert_symlink()     { [ -L "$1" ] && pass "symlink: $1" || fail "not a symlink: $1"; }

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

# ─── Section 1: bin/cds file properties ───────────────────────────────────────

section "bin/cds — file properties"

assert_file_exists "$CDS_BIN"
assert_executable  "$CDS_BIN"

test_cds_has_shebang() {
    local first_line
    first_line=$(head -1 "$CDS_BIN")
    assert_contains "$first_line" "bash" "bin/cds has bash shebang"
}

test_cds_syntax_ok() {
    bash -n "$CDS_BIN" 2>/dev/null && pass "bin/cds syntax OK" || fail "bin/cds syntax error"
}

test_cds_has_set_euo() {
    grep -q 'set -euo pipefail' "$CDS_BIN" && pass "bin/cds uses set -euo pipefail" || fail "bin/cds missing set -euo pipefail"
}

test_cds_launches_openchad() {
    grep -q 'openchad' "$CDS_BIN" && pass "bin/cds references openchad" || fail "bin/cds does not reference openchad"
}

test_cds_does_not_reference_old_name() {
    # bin/cds should not reference the old hyphenated name as a binary
    if grep -qE 'exec open-chad|command -v open-chad|bin/open-chad' "$CDS_BIN"; then
        fail "bin/cds still references old 'open-chad' binary name"
    else
        pass "bin/cds does not reference old 'open-chad' binary name"
    fi
}

test_cds_does_not_launch_raw_opencode() {
    # Should not exec opencode directly — must go through openchad
    if grep -qE '^[[:space:]]*exec opencode' "$CDS_BIN"; then
        fail "bin/cds execs opencode directly (should use openchad)"
    else
        pass "bin/cds does not exec opencode directly"
    fi
}

test_cds_has_shebang
test_cds_syntax_ok
test_cds_has_set_euo
test_cds_launches_openchad
test_cds_does_not_reference_old_name
test_cds_does_not_launch_raw_opencode

# ─── Section 2: --help flag ───────────────────────────────────────────────────

section "bin/cds — --help flag"

test_cds_help_exits_zero() {
    bash "$CDS_BIN" --help >/dev/null 2>&1
    local rc=$?
    assert_eq "$rc" "0" "cds --help exits 0"
}

test_cds_help_output_mentions_scratch() {
    local output
    output=$(bash "$CDS_BIN" --help 2>&1)
    assert_contains "$output" "scratch" "cds --help mentions scratch"
}

test_cds_help_output_mentions_date() {
    local output
    output=$(bash "$CDS_BIN" --help 2>&1)
    assert_contains "$output" "date" "cds --help mentions date"
}

test_cds_help_exits_zero
test_cds_help_output_mentions_scratch
test_cds_help_output_mentions_date

# ─── Section 3: directory creation ───────────────────────────────────────────

section "bin/cds — scratch directory creation"

# We test directory creation by sourcing just the mkdir/cd logic, not the exec.
# We do this by running cds with a fake openchad that exits 0 immediately.

_run_cds_with_fake_launcher() {
    local date_arg="${1:-}"
    local fake_bin="$TMP_DIR/fake_bin"
    mkdir -p "$fake_bin"

    # Fake openchad: just exits 0 without doing anything
    cat > "$fake_bin/openchad" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$fake_bin/openchad"

    # Run cds with PATH pointing to our fake openchad
    # We also override HOME so scratch lands in our temp dir
    if [ -n "$date_arg" ]; then
        HOME="$TMP_DIR/home" PATH="$fake_bin:$PATH" bash "$CDS_BIN" "$date_arg" 2>/dev/null
    else
        HOME="$TMP_DIR/home" PATH="$fake_bin:$PATH" bash "$CDS_BIN" 2>/dev/null
    fi
}

test_cds_creates_today_dir() {
    setup_tmp_env
    local today
    today=$(date +%Y-%m-%d)
    _run_cds_with_fake_launcher || true
    assert_dir_exists "$TMP_DIR/home/scratch/$today"
    teardown_tmp_env
}

test_cds_creates_explicit_date_dir() {
    setup_tmp_env
    _run_cds_with_fake_launcher "2026-01-15" || true
    assert_dir_exists "$TMP_DIR/home/scratch/2026-01-15"
    teardown_tmp_env
}

test_cds_idempotent_dir_creation() {
    setup_tmp_env
    local today
    today=$(date +%Y-%m-%d)
    # Run twice — should not fail on second run
    _run_cds_with_fake_launcher || true
    _run_cds_with_fake_launcher || true
    assert_dir_exists "$TMP_DIR/home/scratch/$today"
    teardown_tmp_env
}

test_cds_creates_today_dir
test_cds_creates_explicit_date_dir
test_cds_idempotent_dir_creation

# ─── Section 4: launch target resolution ─────────────────────────────────────

section "bin/cds — launch target resolution"

test_cds_prefers_sibling_openchad() {
    # The sibling bin/openchad should be preferred over PATH lookup.
    # Verify the script checks for a sibling binary first.
    grep -q 'SCRIPT_DIR' "$CDS_BIN" && pass "bin/cds uses SCRIPT_DIR for sibling lookup" || fail "bin/cds missing SCRIPT_DIR sibling lookup"
}

test_cds_falls_back_to_path() {
    # Verify there is a PATH fallback (command -v openchad or similar)
    grep -q 'command -v openchad' "$CDS_BIN" && pass "bin/cds has PATH fallback for openchad" || fail "bin/cds missing PATH fallback"
}

test_cds_errors_if_no_openchad() {
    setup_tmp_env
    # Run cds with an empty PATH and no sibling (copy cds to a temp location without openchad sibling)
    local isolated_bin="$TMP_DIR/isolated/cds"
    mkdir -p "$(dirname "$isolated_bin")"
    cp "$CDS_BIN" "$isolated_bin"
    chmod +x "$isolated_bin"

    local output
    local rc=0
    output=$(HOME="$TMP_DIR/home" PATH="/usr/bin:/bin" bash "$isolated_bin" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        pass "cds exits non-zero when openchad not found"
    else
        fail "cds should exit non-zero when openchad not found"
    fi
    assert_contains "$output" "ERROR" "cds prints ERROR when openchad not found"
    teardown_tmp_env
}

test_cds_prefers_sibling_openchad
test_cds_falls_back_to_path
test_cds_errors_if_no_openchad

# ─── Section 5: launch passes scratch dir as argument ─────────────────────────

section "bin/cds — passes scratch dir to openchad"

test_cds_passes_scratch_dir_to_launcher() {
    setup_tmp_env
    local today
    today=$(date +%Y-%m-%d)

    # Copy cds to an isolated directory so its sibling lookup finds our fake openchad
    local isolated_dir="$TMP_DIR/isolated_bin"
    mkdir -p "$isolated_dir"
    cp "$CDS_BIN" "$isolated_dir/cds"
    chmod +x "$isolated_dir/cds"

    # Fake openchad placed as sibling: records its arguments to a file
    cat > "$isolated_dir/openchad" <<EOF
#!/usr/bin/env bash
echo "\$@" > "$TMP_DIR/openchad_args"
exit 0
EOF
    chmod +x "$isolated_dir/openchad"

    HOME="$TMP_DIR/home" bash "$isolated_dir/cds" 2>/dev/null || true

    if [ -f "$TMP_DIR/openchad_args" ]; then
        local args
        args=$(cat "$TMP_DIR/openchad_args")
        assert_contains "$args" "scratch/$today" "cds passes scratch dir to openchad"
    else
        fail "cds did not invoke openchad (args file not created)"
    fi
    teardown_tmp_env
}

test_cds_passes_scratch_dir_to_launcher

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
