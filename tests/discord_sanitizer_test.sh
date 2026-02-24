#!/usr/bin/env bash
# tests/discord_sanitizer_test.sh — TDD red-phase tests for discord sanitizer
# Tests: path redaction, token redaction, env var redaction, safe passthrough
#
# Usage: bash tests/discord_sanitizer_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPDATE_JS="$REPO_DIR/lib/discord/update.js"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
skip() { echo "  SKIP: $1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

assert_eq()           { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got='$1', expected='$2')"; }
assert_contains()     { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (looking for '$2' in '$1')"; }
assert_not_contains() { ! echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (unexpectedly found '$2' in '$1')"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Helpers ──────────────────────────────────────────────────────────────────

# Run the sanitizer exported from update.js
# Usage: run_sanitizer "input string"
# Returns: sanitized string via stdout
run_sanitizer() {
    if ! command -v node &>/dev/null; then
        skip "node not available"; return 1
    fi
    if [ ! -f "$UPDATE_JS" ]; then
        fail "update.js not found at $UPDATE_JS (expected — red phase)"; return 1
    fi
    node -e "
const { sanitize } = require('$UPDATE_JS');
process.stdout.write(sanitize(process.argv[1]));
" -- "$1" 2>/dev/null
}

section "Precondition: update.js must expose sanitize()"

test_update_js_exists() {
    [ -f "$UPDATE_JS" ] && pass "update.js exists" || fail "update.js missing at $UPDATE_JS"
}

test_sanitize_exported() {
    if ! command -v node &>/dev/null; then skip "node not available"; return; fi
    if [ ! -f "$UPDATE_JS" ]; then skip "update.js not found (expected red)"; return; fi
    node -e "
const m = require('$UPDATE_JS');
if (typeof m.sanitize !== 'function') { process.exit(1); }
" 2>/dev/null && pass "sanitize() is exported from update.js" || fail "sanitize() not exported from update.js"
}

test_update_js_exists
test_sanitize_exported

# ─── Section 1: Path redaction ───────────────────────────────────────────────

section "Path redaction (SC-7)"

test_redacts_linux_home_path() {
    local result
    result=$(run_sanitizer "/home/jrade/dev/secret-project") || return
    assert_not_contains "$result" "/home/jrade" "linux home path is redacted"
    assert_contains "$result" "[REDACTED]" "linux home path replaced with [REDACTED]"
}

test_redacts_macos_home_path() {
    local result
    result=$(run_sanitizer "/Users/alice/Projects/proprietary") || return
    assert_not_contains "$result" "/Users/alice" "macOS home path is redacted"
    assert_contains "$result" "[REDACTED]" "macOS home path replaced with [REDACTED]"
}

test_redacts_tilde_home_path() {
    local result
    result=$(run_sanitizer "~/dev/open-chad") || return
    assert_not_contains "$result" "~/dev" "tilde home path is redacted"
    assert_contains "$result" "[REDACTED]" "tilde path replaced with [REDACTED]"
}

test_safe_string_not_redacted() {
    local result
    result=$(run_sanitizer "Chadding hard") || return
    assert_eq "$result" "Chadding hard" "safe string passes through unchanged"
}

test_session_count_not_redacted() {
    local result
    result=$(run_sanitizer "3 sessions · 47m") || return
    assert_eq "$result" "3 sessions · 47m" "session count + elapsed time unchanged"
}

test_redacts_root_path() {
    local result
    result=$(run_sanitizer "/root/secrets/private.key") || return
    assert_not_contains "$result" "/root/secrets" "root path is redacted"
    assert_contains "$result" "[REDACTED]" "root path replaced with [REDACTED]"
}

test_redacts_linux_home_path
test_redacts_macos_home_path
test_redacts_tilde_home_path
test_redacts_root_path
test_safe_string_not_redacted
test_session_count_not_redacted

# ─── Section 2: Token redaction (SC-8) ───────────────────────────────────────

section "Token redaction (SC-8)"

test_redacts_sk_prefix_token() {
    local result
    result=$(run_sanitizer "sk-proj-abcdefghijklmnopqrstuvwxyz") || return
    assert_not_contains "$result" "sk-proj" "sk- prefixed token is redacted"
    assert_contains "$result" "[REDACTED]" "sk- token replaced with [REDACTED]"
}

test_redacts_github_token() {
    local result
    result=$(run_sanitizer "ghp_abcdefghijklmnopqrstuvwxyz12345") || return
    assert_not_contains "$result" "ghp_" "GitHub token is redacted"
    assert_contains "$result" "[REDACTED]" "GitHub token replaced with [REDACTED]"
}

test_redacts_aws_access_key() {
    local result
    result=$(run_sanitizer "AKIAIOSFODNN7EXAMPLE") || return
    assert_not_contains "$result" "AKIA" "AWS access key is redacted"
    assert_contains "$result" "[REDACTED]" "AWS key replaced with [REDACTED]"
}

test_redacts_long_alnum_token() {
    local result
    result=$(run_sanitizer "abcdefghijklmnopqrstu") || return  # 21 chars
    assert_not_contains "$result" "abcdefghijklmnopqrstu" "long alphanumeric token (21 chars) is redacted"
    assert_contains "$result" "[REDACTED]" "long token replaced with [REDACTED]"
}

test_short_alnum_not_redacted() {
    local result
    result=$(run_sanitizer "abc123") || return  # 6 chars — safe
    assert_eq "$result" "abc123" "short alphanumeric string (6 chars) passes through"
}

test_redacts_sk_prefix_token
test_redacts_github_token
test_redacts_aws_access_key
test_redacts_long_alnum_token
test_short_alnum_not_redacted

# ─── Section 3: Env var redaction (SC-9) ─────────────────────────────────────

section "Environment variable redaction (SC-9)"

test_redacts_dollar_brace_var() {
    local result
    result=$(run_sanitizer 'Using ${GITHUB_TOKEN}') || return
    assert_not_contains "$result" 'GITHUB_TOKEN' "brace env var is redacted"
    assert_contains "$result" "[REDACTED]" "brace env var replaced with [REDACTED]"
}

test_redacts_dollar_var() {
    local result
    result=$(run_sanitizer 'key is $SECRET_KEY') || return
    assert_not_contains "$result" 'SECRET_KEY' "bare dollar env var is redacted"
    assert_contains "$result" "[REDACTED]" "bare dollar var replaced with [REDACTED]"
}

test_redacts_dollar_var_inline() {
    local result
    result=$(run_sanitizer 'token=abc $MY_VAR xyz') || return
    assert_not_contains "$result" 'MY_VAR' "inline env var is redacted"
    assert_contains "$result" "[REDACTED]" "inline env var replaced with [REDACTED]"
}

test_dollar_number_not_redacted() {
    local result
    result=$(run_sanitizer '$1 sessions active') || return
    # $1 is a shell positional param, not a named env var — should pass through
    # (named vars have uppercase letters/underscore pattern: $[A-Z_][A-Z0-9_]*)
    assert_not_contains "$result" "[REDACTED]" "dollar-number positional param not over-redacted"
}

test_redacts_dollar_brace_var
test_redacts_dollar_var
test_redacts_dollar_var_inline
test_dollar_number_not_redacted

# ─── Section 4: Combined / edge cases ────────────────────────────────────────

section "Combined and edge cases"

test_empty_string_passthrough() {
    local result
    result=$(run_sanitizer "") || return
    assert_eq "$result" "" "empty string returns empty string"
}

test_multiple_patterns_all_redacted() {
    local result
    result=$(run_sanitizer "/home/alice/dev sk-abc12345678901234567 \$MY_VAR") || return
    assert_not_contains "$result" "/home/alice" "path redacted in compound input"
    assert_not_contains "$result" "sk-abc" "token redacted in compound input"
    assert_not_contains "$result" "MY_VAR" "env var redacted in compound input"
}

test_tagline_survives_sanitizer() {
    local result
    result=$(run_sanitizer "AI chaos coordination") || return
    assert_eq "$result" "AI chaos coordination" "tagline passes through sanitizer unchanged"
}

test_numeric_elapsed_survives() {
    local result
    result=$(run_sanitizer "1h 23m elapsed") || return
    assert_eq "$result" "1h 23m elapsed" "elapsed time string passes through unchanged"
}

test_empty_string_passthrough
test_multiple_patterns_all_redacted
test_tagline_survives_sanitizer
test_numeric_elapsed_survives

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed, $TESTS_SKIPPED skipped"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
