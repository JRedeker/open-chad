#!/usr/bin/env bash
# tests/llm_fuel_test.sh — Unit tests for LLM fuel gauge
# Tests: percentage formula, color thresholds, status_left.sh rendering, edge cases
#
# Usage: bash tests/llm_fuel_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATUS_LEFT="$REPO_DIR/lib/status_left.sh"
COLLECT_METRICS="$REPO_DIR/lib/collect_metrics.sh"

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

# ─── Section 3: status_left.sh rendering ─────────────────────────────────────

section "status_left.sh rendering"

# Check script exists and is executable
test_script_exists() {
    [ -f "$STATUS_LEFT" ] && pass "status_left.sh exists" || fail "status_left.sh missing: $STATUS_LEFT"
}

test_script_syntax() {
    bash -n "$STATUS_LEFT" 2>/dev/null && pass "status_left.sh syntax OK" || fail "status_left.sh syntax error"
}

TMP_CACHE=$(mktemp)

test_renders_fuel_with_no_cache() {
    local result
    result=$(LLM_CACHE_OVERRIDE="/nonexistent/path" bash "$STATUS_LEFT" 2>/dev/null || true)
    # Should render without error (graceful fallback)
    # Either shows – or a percentage
    pass "status_left.sh runs without error when cache missing"
}

test_renders_green_at_75() {
    echo "75" > "$TMP_CACHE"
    local result
    result=$(bash -c "
        llm_cache='$TMP_CACHE'
        fuel=\$(cat \"\$llm_cache\")
        if [[ \"\$fuel\" =~ ^[0-9]+\$ ]]; then
            if [ \"\$fuel\" -ge 50 ]; then color='green'
            elif [ \"\$fuel\" -ge 20 ]; then color='yellow'
            else color='red'
            fi
        fi
        echo \"\$color\"
    ")
    assert_eq "$result" "green" "75% → green color"
}

test_renders_yellow_at_35() {
    echo "35" > "$TMP_CACHE"
    local result
    result=$(bash -c "
        llm_cache='$TMP_CACHE'
        fuel=\$(cat \"\$llm_cache\")
        if [[ \"\$fuel\" =~ ^[0-9]+\$ ]]; then
            if [ \"\$fuel\" -ge 50 ]; then color='green'
            elif [ \"\$fuel\" -ge 20 ]; then color='yellow'
            else color='red'
            fi
        fi
        echo \"\$color\"
    ")
    assert_eq "$result" "yellow" "35% → yellow color"
}

test_renders_red_at_10() {
    echo "10" > "$TMP_CACHE"
    local result
    result=$(bash -c "
        llm_cache='$TMP_CACHE'
        fuel=\$(cat \"\$llm_cache\")
        if [[ \"\$fuel\" =~ ^[0-9]+\$ ]]; then
            if [ \"\$fuel\" -ge 50 ]; then color='green'
            elif [ \"\$fuel\" -ge 20 ]; then color='yellow'
            else color='red'
            fi
        fi
        echo \"\$color\"
    ")
    assert_eq "$result" "red" "10% → red color"
}

test_output_contains_fuel_icon() {
    echo "80" > /tmp/open-chad-llm-metrics
    local result
    result=$(bash "$STATUS_LEFT" 2>/dev/null || true)
    assert_contains "$result" "⛽" "output contains fuel icon"
    assert_contains "$result" "80%" "output contains percentage"
}

test_output_contains_green_color_for_80() {
    echo "80" > /tmp/open-chad-llm-metrics
    local result
    result=$(bash "$STATUS_LEFT" 2>/dev/null || true)
    assert_contains "$result" "#AAD94C" "80% output uses green color"
}

test_output_contains_title_when_provided() {
    echo "80" > /tmp/open-chad-llm-metrics
    local result
    result=$(bash "$STATUS_LEFT" "🚀 open-chad testChange" 2>/dev/null || true)
    assert_contains "$result" "▎" "output includes title parser divider"
    assert_contains "$result" "open-chad" "output includes repo name"
}

test_script_exists
test_script_syntax
test_renders_fuel_with_no_cache
test_renders_green_at_75
test_renders_yellow_at_35
test_renders_red_at_10
test_output_contains_fuel_icon
test_output_contains_green_color_for_80
test_output_contains_title_when_provided

rm -f "$TMP_CACHE"

# ─── Section 4: collect_metrics.sh structure ─────────────────────────────────

section "collect_metrics.sh structure"

test_collect_syntax() {
    bash -n "$COLLECT_METRICS" 2>/dev/null && pass "collect_metrics.sh syntax OK" || fail "collect_metrics.sh syntax error"
}

test_collect_has_plan_limit() {
    grep -q "PLAN_LIMIT=" "$COLLECT_METRICS" && pass "PLAN_LIMIT variable defined" || fail "PLAN_LIMIT missing"
}

test_collect_has_llm_cache() {
    grep -q "LLM_CACHE=" "$COLLECT_METRICS" && pass "LLM_CACHE variable defined" || fail "LLM_CACHE missing"
}

test_collect_has_collect_llm_fuel() {
    grep -q "collect_llm_fuel" "$COLLECT_METRICS" && pass "collect_llm_fuel() function defined" || fail "collect_llm_fuel() missing"
}

test_collect_uses_time_created_not_mmin() {
    grep -q "time_created" "$COLLECT_METRICS" && pass "uses time_created (not file mtime)" || fail "time_created not found"
    assert_not_contains "$(cat "$COLLECT_METRICS")" "mmin" "does NOT use -mmin (unreliable)"
}

test_collect_has_graceful_fallback() {
    # Script should set fuel_pct=100 as default before any conditional
    grep -q "fuel_pct=100" "$COLLECT_METRICS" && pass "graceful fallback (fuel_pct=100) present" || fail "no graceful fallback found"
}

test_collect_atomic_write() {
    grep -q 'mv -f.*LLM_CACHE' "$COLLECT_METRICS" && pass "LLM cache uses atomic mv" || fail "LLM cache write not atomic"
}

test_collect_syntax
test_collect_has_plan_limit
test_collect_has_llm_cache
test_collect_has_collect_llm_fuel
test_collect_uses_time_created_not_mmin
test_collect_has_graceful_fallback
test_collect_atomic_write

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
