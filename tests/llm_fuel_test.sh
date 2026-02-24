#!/usr/bin/env bash
# tests/llm_fuel_test.sh — Unit tests for LLM fuel gauge
# Tests: percentage formula, color thresholds, status_left.sh rendering, edge cases,
#        per-provider multi-gauge, API response parsing, partial failure scenarios
#
# Usage: bash tests/llm_fuel_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATUS_LEFT="$REPO_DIR/lib/status_left.sh"
COLLECT_METRICS="$REPO_DIR/lib/collect_metrics.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (looking for '$2' in '$1')"; }
assert_not_contains() { ! echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (unexpectedly found '$2' in '$1')"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Simulate the fuel percentage calculation formula used in collect_metrics.sh
calc_fuel_pct() {
    local used_tokens="$1"
    local plan_limit="$2"
    local fuel_pct=100

    if ! [[ "${used_tokens:-0}" =~ ^[0-9]+$ ]]; then
        used_tokens=0
    fi

    if [ "${used_tokens:-0}" -ge "$plan_limit" ]; then
        fuel_pct=0
    elif [ "$plan_limit" -gt 0 ]; then
        fuel_pct=$(( 100 - (used_tokens * 100 / plan_limit) ))
        [ "$fuel_pct" -lt 0 ] && fuel_pct=0
        [ "$fuel_pct" -gt 100 ] && fuel_pct=100
    fi

    echo "$fuel_pct"
}

# ─── Section 1: Percentage formula ───────────────────────────────────────────

section "Fuel percentage calculation"

PLAN=44000

test_zero_usage() {
    local pct
    pct=$(calc_fuel_pct 0 "$PLAN")
    assert_eq "$pct" "100" "zero usage → 100% full"
}

test_full_usage() {
    local pct
    pct=$(calc_fuel_pct "$PLAN" "$PLAN")
    assert_eq "$pct" "0" "100% used → 0% remaining"
}

test_half_usage() {
    local pct
    pct=$(calc_fuel_pct 22000 "$PLAN")
    assert_eq "$pct" "50" "50% used → 50% remaining"
}

test_near_full_usage() {
    local pct
    pct=$(calc_fuel_pct 43000 "$PLAN")
    # Integer division: 100 - (43000 * 100 / 44000) = 100 - 97 = 3
    assert_eq "$pct" "3" "nearly full usage → ~3% remaining"
}

test_over_limit_clamped() {
    local pct
    pct=$(calc_fuel_pct $(( PLAN * 2 )) "$PLAN")
    assert_eq "$pct" "0" "over-limit usage → clamped to 0"
}

test_invalid_tokens_fallback() {
    local pct
    pct=$(calc_fuel_pct "abc" "$PLAN")
    assert_eq "$pct" "100" "invalid token string → fallback to 100"
}

test_zero_usage
test_full_usage
test_half_usage
test_near_full_usage
test_over_limit_clamped
test_invalid_tokens_fallback

# ─── Section 2: Color threshold logic ────────────────────────────────────────

section "Color threshold mapping"

get_color() {
    local fuel="$1"
    if [ "$fuel" -ge 50 ]; then
        echo "#AAD94C"   # green
    elif [ "$fuel" -ge 20 ]; then
        echo "#E6B450"   # yellow
    else
        echo "#FF8F40"   # red
    fi
}

test_color_green_50() {
    assert_eq "$(get_color 50)" "#AAD94C" "50% → green"
}

test_color_green_100() {
    assert_eq "$(get_color 100)" "#AAD94C" "100% → green"
}

test_color_yellow_20() {
    assert_eq "$(get_color 20)" "#E6B450" "20% → yellow"
}

test_color_yellow_49() {
    assert_eq "$(get_color 49)" "#E6B450" "49% → yellow"
}

test_color_red_19() {
    assert_eq "$(get_color 19)" "#FF8F40" "19% → red"
}

test_color_red_0() {
    assert_eq "$(get_color 0)" "#FF8F40" "0% → red"
}

test_color_green_50
test_color_green_100
test_color_yellow_20
test_color_yellow_49
test_color_red_19
test_color_red_0

# ─── Section 3: status_left.sh rendering (multi-provider) ────────────────────

section "status_left.sh rendering"

# Check script exists and is executable
test_script_exists() {
    [ -f "$STATUS_LEFT" ] && pass "status_left.sh exists" || fail "status_left.sh missing: $STATUS_LEFT"
}

test_script_syntax() {
    bash -n "$STATUS_LEFT" 2>/dev/null && pass "status_left.sh syntax OK" || fail "status_left.sh syntax error"
}

# Set up isolated tmp dir for cache files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

ZAI_CACHE="$TMP_DIR/open-chad-zai"
COPILOT_CACHE="$TMP_DIR/open-chad-copilot"
CLAUDE_CACHE="$TMP_DIR/open-chad-claude"
CODEX_CACHE="$TMP_DIR/open-chad-codex"

# Helper: run status_left.sh with overridden cache paths
run_status_left() {
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_LEFT" "$@" 2>/dev/null || true
}

# Helper: force-enable gauge regardless of cache state
run_status_left_force() {
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_LEFT" "$@" 2>/dev/null || true
}

test_renders_all_dash_when_no_caches_forced() {
    rm -f "$ZAI_CACHE" "$COPILOT_CACHE" "$CLAUDE_CACHE" "$CODEX_CACHE"
    local result
    result=$(run_status_left_force)
    assert_contains "$result" "Z.ai" "force-on: Z.ai label shown even with no caches"
    assert_contains "$result" "Copilot" "force-on: Copilot label shown even with no caches"
    assert_contains "$result" "Claude" "force-on: Claude label shown even with no caches"
    assert_contains "$result" "Codex" "force-on: Codex label shown even with no caches"
}

test_auto_hides_when_no_caches() {
    rm -f "$ZAI_CACHE" "$COPILOT_CACHE" "$CLAUDE_CACHE" "$CODEX_CACHE"
    local result
    result=$(run_status_left)
    assert_eq "$result" "" "auto mode: empty output when no cache files exist"
}

test_exits_zero_with_no_caches() {
    rm -f "$ZAI_CACHE" "$COPILOT_CACHE" "$CLAUDE_CACHE" "$CODEX_CACHE"
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_LEFT" >/dev/null 2>&1
    assert_eq "$?" "0" "status_left.sh exits 0 with no caches"
}

test_renders_green_for_75() {
    printf '75' > "$ZAI_CACHE"
    local result
    result=$(run_status_left)
    assert_contains "$result" "#AAD94C" "Z.ai 75% → green color"
    assert_contains "$result" "75%" "Z.ai 75% shown"
}

test_renders_yellow_for_35() {
    printf '35' > "$COPILOT_CACHE"
    local result
    result=$(run_status_left)
    assert_contains "$result" "#E6B450" "Copilot 35% → yellow color"
    assert_contains "$result" "35%" "Copilot 35% shown"
}

test_renders_red_for_10() {
    printf '10' > "$CLAUDE_CACHE"
    local result
    result=$(run_status_left)
    assert_contains "$result" "#FF8F40" "Claude 10% → red color"
    assert_contains "$result" "10%" "Claude 10% shown"
}

test_renders_dash_for_empty_cache() {
    # Need at least one valid peer cache to trigger auto-enable
    printf '80' > "$ZAI_CACHE"
    printf '' > "$CODEX_CACHE"
    local result
    result=$(run_status_left)
    # Gauge is shown (ZAI has data), Codex should show -- not a percentage
    assert_contains "$result" "Codex" "Codex label present for empty cache"
}

test_renders_dash_for_non_integer_cache() {
    # Need at least one valid peer cache to trigger auto-enable
    printf '80' > "$COPILOT_CACHE"
    printf 'error' > "$ZAI_CACHE"
    local result
    result=$(run_status_left)
    assert_contains "$result" "Z.ai" "Z.ai label present for non-integer cache"
    assert_not_contains "$result" "error%" "non-integer cache does not render as percent"
}

test_four_segments_separated_by_pipe() {
    printf '62' > "$ZAI_CACHE"
    printf '81' > "$COPILOT_CACHE"
    printf '47' > "$CLAUDE_CACHE"
    printf '94' > "$CODEX_CACHE"
    local result
    result=$(run_status_left)
    assert_contains "$result" "Z.ai" "output contains Z.ai segment"
    assert_contains "$result" "Copilot" "output contains Copilot segment"
    assert_contains "$result" "Claude" "output contains Claude segment"
    assert_contains "$result" "Codex" "output contains Codex segment"
    assert_contains "$result" "|" "output contains segment separator"
}

test_output_contains_title_when_provided() {
    printf '80' > "$ZAI_CACHE"
    local result
    result=$(run_status_left "🚀 open-chad testChange" 2>/dev/null || true)
    assert_contains "$result" "open-chad" "output includes repo name"
}

test_script_exists
test_script_syntax
test_renders_all_dash_when_no_caches_forced
test_auto_hides_when_no_caches
test_exits_zero_with_no_caches
test_renders_green_for_75
test_renders_yellow_for_35
test_renders_red_for_10
test_renders_dash_for_empty_cache
test_renders_dash_for_non_integer_cache
test_four_segments_separated_by_pipe
test_output_contains_title_when_provided

# ─── Section 4: API response parsing helpers ──────────────────────────────────

section "API response parsing (extract_percent helpers)"

# Helper: simulate extract_zai_percent (from fixture JSON)
extract_zai_percent() {
    local json="$1"
    echo "$json" | jq -r '
        .data.limits[]
        | select(.type == "TOKENS_LIMIT")
        | .percentage
        | if . == null then empty else (100 - .) | floor end
    ' 2>/dev/null || true
}

# Helper: simulate extract_copilot_percent (from fixture JSON), clamping negatives
extract_copilot_percent() {
    local json="$1"
    local raw
    raw=$(echo "$json" | jq -r '
        .quota_snapshots.premium_interactions.percent_remaining
        | if . == null then empty else . end
    ' 2>/dev/null || true)
    [ -z "$raw" ] && return
    # Clamp to [0, 100] — value can be negative when over quota
    local pct
    pct=$(echo "$raw" | awk '{v=int($1); if(v<0) v=0; if(v>100) v=100; print v}')
    echo "$pct"
}

# Helper: simulate extract_claude_percent (from fixture JSON)
extract_claude_percent() {
    local json="$1"
    echo "$json" | jq -r '
        .five_hour.utilization
        | if . == null then empty else (100 - .) | floor end
    ' 2>/dev/null || true
}

# Helper: simulate extract_codex_percent (from fixture JSON)
extract_codex_percent() {
    local json="$1"
    echo "$json" | jq -r '
        .rate_limit.primary_window.used_percent
        | if . == null then empty else (100 - .) end
    ' 2>/dev/null || true
}

test_zai_extract_from_fixture() {
    local fixture
    fixture='{"code":200,"msg":"Operation successful","data":{"limits":[{"type":"TIME_LIMIT","unit":5,"number":1,"usage":4000,"currentValue":0,"remaining":4000,"percentage":0},{"type":"TOKENS_LIMIT","unit":3,"number":5,"percentage":1}]},"success":true}'
    local pct
    pct=$(extract_zai_percent "$fixture")
    assert_eq "$pct" "99" "Z.ai: 1% used → 99% remaining"
}

test_zai_extract_zero_usage() {
    local fixture
    fixture='{"code":200,"data":{"limits":[{"type":"TOKENS_LIMIT","percentage":0}]},"success":true}'
    local pct
    pct=$(extract_zai_percent "$fixture")
    assert_eq "$pct" "100" "Z.ai: 0% used → 100% remaining"
}

test_copilot_extract_from_fixture() {
    local fixture
    fixture='{"quota_snapshots":{"premium_interactions":{"percent_remaining":83.5}}}'
    local pct
    pct=$(extract_copilot_percent "$fixture")
    assert_eq "$pct" "83" "Copilot: 83.5% remaining → 83 (floor)"
}

test_copilot_clamp_negative() {
    local fixture
    fixture='{"quota_snapshots":{"premium_interactions":{"percent_remaining":-83.67}}}'
    local pct
    pct=$(extract_copilot_percent "$fixture")
    assert_eq "$pct" "0" "Copilot: negative percent_remaining → clamped to 0"
}

test_claude_extract_from_fixture() {
    local fixture
    fixture='{"five_hour":{"utilization":5.0,"resets_at":"2026-02-24T08:00:00Z"},"seven_day":{"utilization":58.0}}'
    local pct
    pct=$(extract_claude_percent "$fixture")
    assert_eq "$pct" "95" "Claude: 5% used → 95% remaining"
}

test_claude_extract_full_usage() {
    local fixture
    fixture='{"five_hour":{"utilization":100.0,"resets_at":"2026-02-24T08:00:00Z"}}'
    local pct
    pct=$(extract_claude_percent "$fixture")
    assert_eq "$pct" "0" "Claude: 100% used → 0% remaining"
}

test_codex_extract_from_fixture() {
    local fixture
    fixture='{"rate_limit":{"primary_window":{"used_percent":6,"limit_window_seconds":18000}}}'
    local pct
    pct=$(extract_codex_percent "$fixture")
    assert_eq "$pct" "94" "Codex: 6% used → 94% remaining"
}

test_codex_extract_zero_usage() {
    local fixture
    fixture='{"rate_limit":{"primary_window":{"used_percent":0}}}'
    local pct
    pct=$(extract_codex_percent "$fixture")
    assert_eq "$pct" "100" "Codex: 0% used → 100% remaining"
}

test_zai_extract_from_fixture
test_zai_extract_zero_usage
test_copilot_extract_from_fixture
test_copilot_clamp_negative
test_claude_extract_from_fixture
test_claude_extract_full_usage
test_codex_extract_from_fixture
test_codex_extract_zero_usage

# ─── Section 5: Failure / error scenarios ────────────────────────────────────

section "Provider failure and error scenarios"

test_zai_empty_on_bad_json() {
    local pct
    pct=$(extract_zai_percent "not valid json")
    assert_eq "$pct" "" "Z.ai: invalid JSON → empty (→ -- in display)"
}

test_copilot_empty_on_missing_field() {
    local pct
    pct=$(extract_copilot_percent '{"quota_snapshots":{}}')
    assert_eq "$pct" "" "Copilot: missing premium_interactions → empty"
}

test_claude_empty_on_bad_json() {
    local pct
    pct=$(extract_claude_percent "")
    assert_eq "$pct" "" "Claude: empty input → empty"
}

test_codex_empty_on_missing_field() {
    local pct
    pct=$(extract_codex_percent '{"rate_limit":{}}')
    assert_eq "$pct" "" "Codex: missing primary_window → empty"
}

test_zai_empty_on_bad_json
test_copilot_empty_on_missing_field
test_claude_empty_on_bad_json
test_codex_empty_on_missing_field

# ─── Section 6: Partial provider failure ─────────────────────────────────────

section "Partial provider failure (3 succeed, 1 fails)"

test_partial_failure_renders_all_four_segments() {
    # 3 caches have values, codex is empty (failed)
    printf '62' > "$ZAI_CACHE"
    printf '81' > "$COPILOT_CACHE"
    printf '47' > "$CLAUDE_CACHE"
    printf '' > "$CODEX_CACHE"   # simulated failure

    local result
    result=$(run_status_left)
    assert_contains "$result" "Z.ai" "partial failure: Z.ai segment present"
    assert_contains "$result" "Copilot" "partial failure: Copilot segment present"
    assert_contains "$result" "Claude" "partial failure: Claude segment present"
    assert_contains "$result" "Codex" "partial failure: Codex segment present"
    assert_contains "$result" "62%" "partial failure: Z.ai shows 62%"
    assert_contains "$result" "81%" "partial failure: Copilot shows 81%"
    assert_contains "$result" "47%" "partial failure: Claude shows 47%"
}

test_exits_zero_on_partial_failure() {
    printf '62' > "$ZAI_CACHE"
    printf '81' > "$COPILOT_CACHE"
    printf '47' > "$CLAUDE_CACHE"
    printf '' > "$CODEX_CACHE"
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_LEFT" >/dev/null 2>&1
    assert_eq "$?" "0" "status_left.sh exits 0 on partial failure"
}

test_partial_failure_renders_all_four_segments
test_exits_zero_on_partial_failure

# ─── Section 7: collect_metrics.sh structure ─────────────────────────────────

section "collect_metrics.sh structure"

test_collect_syntax() {
    bash -n "$COLLECT_METRICS" 2>/dev/null && pass "collect_metrics.sh syntax OK" || fail "collect_metrics.sh syntax error"
}

test_collect_has_four_adapters() {
    grep -q "collect_zai"     "$COLLECT_METRICS" && pass "collect_zai() defined"     || fail "collect_zai() missing"
    grep -q "collect_copilot" "$COLLECT_METRICS" && pass "collect_copilot() defined" || fail "collect_copilot() missing"
    grep -q "collect_claude"  "$COLLECT_METRICS" && pass "collect_claude() defined"  || fail "collect_claude() missing"
    grep -q "collect_codex"   "$COLLECT_METRICS" && pass "collect_codex() defined"   || fail "collect_codex() missing"
}

test_collect_has_four_cache_files() {
    grep -q "open-chad-zai"     "$COLLECT_METRICS" && pass "open-chad-zai cache defined"     || fail "open-chad-zai missing"
    grep -q "open-chad-copilot" "$COLLECT_METRICS" && pass "open-chad-copilot cache defined" || fail "open-chad-copilot missing"
    grep -q "open-chad-claude"  "$COLLECT_METRICS" && pass "open-chad-claude cache defined"  || fail "open-chad-claude missing"
    grep -q "open-chad-codex"   "$COLLECT_METRICS" && pass "open-chad-codex cache defined"   || fail "open-chad-codex missing"
}

test_collect_no_bare_wait() {
    # Must NOT have a bare `wait` without a PID (unsafe under set -euo pipefail)
    # Allow `wait $pid_*` patterns but not bare `wait` alone on a line
    if grep -qE '^\s*wait\s*$' "$COLLECT_METRICS"; then
        fail "collect_metrics.sh contains bare 'wait' (unsafe — use 'wait \$pid || rc=\$?')"
    else
        pass "collect_metrics.sh has no bare 'wait' (safe parallel pattern)"
    fi
}

test_collect_uses_auth_json() {
    grep -q "auth.json" "$COLLECT_METRICS" && pass "collect_metrics.sh reads auth.json" || fail "auth.json not referenced"
}

test_collect_atomic_writes() {
    grep -q 'mv -f' "$COLLECT_METRICS" && pass "collect_metrics.sh uses atomic mv writes" || fail "atomic mv writes not found"
}

test_collect_max_time() {
    grep -q -- '--max-time' "$COLLECT_METRICS" && pass "curl uses --max-time timeout" || fail "--max-time not found in curl calls"
}

test_collect_no_old_llm_fuel() {
    grep -q "collect_llm_fuel" "$COLLECT_METRICS" && fail "collect_llm_fuel() still present (should be removed)" || pass "collect_llm_fuel() removed"
}

test_collect_syntax
test_collect_has_four_adapters
test_collect_has_four_cache_files
test_collect_no_bare_wait
test_collect_uses_auth_json
test_collect_atomic_writes
test_collect_max_time
test_collect_no_old_llm_fuel

# ─── Section 8: OPEN_CHAD_MULTI_GAUGE toggle ─────────────────────────────────

section "OPEN_CHAD_MULTI_GAUGE toggle"

test_toggle_off_hides_gauge() {
    printf '80' > "$ZAI_CACHE"
    printf '80' > "$COPILOT_CACHE"
    printf '80' > "$CLAUDE_CACHE"
    printf '80' > "$CODEX_CACHE"
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=0 bash "$STATUS_LEFT" 2>/dev/null || true)
    assert_eq "$result" "" "MULTI_GAUGE=0: gauge hidden even when all caches have data"
}

test_toggle_off_variants() {
    printf '80' > "$ZAI_CACHE"
    local r_false r_no r_off
    r_false=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=false bash "$STATUS_LEFT" 2>/dev/null || true)
    r_no=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR"    OPEN_CHAD_MULTI_GAUGE=no    bash "$STATUS_LEFT" 2>/dev/null || true)
    r_off=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR"   OPEN_CHAD_MULTI_GAUGE=off   bash "$STATUS_LEFT" 2>/dev/null || true)
    assert_eq "$r_false" "" "MULTI_GAUGE=false: gauge hidden"
    assert_eq "$r_no"    "" "MULTI_GAUGE=no: gauge hidden"
    assert_eq "$r_off"   "" "MULTI_GAUGE=off: gauge hidden"
}

test_toggle_on_shows_dashes_with_no_caches() {
    rm -f "$ZAI_CACHE" "$COPILOT_CACHE" "$CLAUDE_CACHE" "$CODEX_CACHE"
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_LEFT" 2>/dev/null || true)
    assert_contains "$result" "Z.ai"    "MULTI_GAUGE=1: Z.ai shown even with no caches"
    assert_contains "$result" "Copilot" "MULTI_GAUGE=1: Copilot shown even with no caches"
    assert_contains "$result" "Claude"  "MULTI_GAUGE=1: Claude shown even with no caches"
    assert_contains "$result" "Codex"   "MULTI_GAUGE=1: Codex shown even with no caches"
}

test_auto_shows_when_one_cache_has_data() {
    rm -f "$ZAI_CACHE" "$COPILOT_CACHE" "$CLAUDE_CACHE" "$CODEX_CACHE"
    printf '55' > "$CLAUDE_CACHE"   # only Claude has data
    local result
    result=$(run_status_left)
    assert_contains "$result" "Claude" "auto mode: gauge visible when at least one cache has data"
    assert_contains "$result" "Z.ai"   "auto mode: all 4 segments shown once any cache has data"
}

test_collect_has_multi_gauge_toggle() {
    grep -q "_multi_gauge_enabled\|OPEN_CHAD_MULTI_GAUGE" "$COLLECT_METRICS" \
        && pass "collect_metrics.sh has OPEN_CHAD_MULTI_GAUGE support" \
        || fail "collect_metrics.sh missing OPEN_CHAD_MULTI_GAUGE toggle"
}

test_status_left_has_multi_gauge_toggle() {
    grep -q "_multi_gauge_enabled\|OPEN_CHAD_MULTI_GAUGE" "$STATUS_LEFT" \
        && pass "status_left.sh has OPEN_CHAD_MULTI_GAUGE support" \
        || fail "status_left.sh missing OPEN_CHAD_MULTI_GAUGE toggle"
}

test_toggle_off_hides_gauge
test_toggle_off_variants
test_toggle_on_shows_dashes_with_no_caches
test_auto_shows_when_one_cache_has_data
test_collect_has_multi_gauge_toggle
test_status_left_has_multi_gauge_toggle

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
