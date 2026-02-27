#!/usr/bin/env bash
# tests/llm_fuel_test.sh — Unit tests for LLM fuel gauge
# Tests: percentage formula, color thresholds, status_right.sh rendering, edge cases,
#        per-provider multi-gauge, API response parsing, partial failure scenarios
#
# Usage: bash tests/llm_fuel_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATUS_LEFT="$REPO_DIR/lib/status_left.sh"
STATUS_RIGHT="$REPO_DIR/lib/status_right.sh"
STATUS_RESOURCES="$REPO_DIR/lib/status_resources.sh"
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

# ─── Section 3: status_right.sh rendering (multi-provider) ────────────────────

section "status_right.sh rendering"

# Check script exists and is executable
test_script_exists() {
    [ -f "$STATUS_LEFT" ] && pass "status_left.sh exists" || fail "status_left.sh missing: $STATUS_LEFT"
}

test_script_syntax() {
    bash -n "$STATUS_LEFT" 2>/dev/null && pass "status_left.sh syntax OK" || fail "status_left.sh syntax error"
}

test_right_script_exists() {
    [ -f "$STATUS_RIGHT" ] && pass "status_right.sh exists" || fail "status_right.sh missing: $STATUS_RIGHT"
}

test_right_script_syntax() {
    bash -n "$STATUS_RIGHT" 2>/dev/null && pass "status_right.sh syntax OK" || fail "status_right.sh syntax error"
}

# Set up isolated tmp dir for cache files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Helper: run status_right.sh with overridden cache paths
run_status_right() {
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" "$@" 2>/dev/null || true
}

# Helper: force-enable gauge regardless of cache state
run_status_right_force() {
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_RIGHT" "$@" 2>/dev/null || true
}

test_renders_all_dash_when_no_caches_forced() {
    local result
    # Mock active_providers to include all 4
    printf "Z.ai zai\nCopilot copilot\nClaude claude\nCodex codex\n" > "$TMP_DIR/active_providers"
    result=$(run_status_right_force)
    assert_contains "$result" "Z.ai" "force-on: Z.ai label shown even with no caches"
    assert_contains "$result" "Copilot" "force-on: Copilot label shown even with no caches"
    assert_contains "$result" "Claude" "force-on: Claude label shown even with no caches"
    assert_contains "$result" "Codex" "force-on: Codex label shown even with no caches"
}

test_auto_hides_when_no_caches() {
    local result
    printf "Z.ai zai\nCopilot copilot\nClaude claude\nCodex codex\n" > "$TMP_DIR/active_providers"
    result=$(run_status_right)
    # Accent edges always render; gauge labels should be absent with no cache data
    assert_not_contains "$result" "Z.ai"    "auto mode: Z.ai label hidden when no cache files"
    assert_not_contains "$result" "Copilot" "auto mode: Copilot label hidden when no cache files"
    assert_not_contains "$result" "Claude"  "auto mode: Claude label hidden when no cache files"
    assert_not_contains "$result" "Codex"   "auto mode: Codex label hidden when no cache files"
    assert_contains "$result" "▐" "auto mode: accent edges always present"
}

test_exits_zero_with_no_caches() {
    printf "Z.ai zai\nCopilot copilot\nClaude claude\nCodex codex\n" > "$TMP_DIR/active_providers"
    OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" >/dev/null 2>&1
    assert_eq "$?" "0" "status_right.sh exits 0 with no caches"
}

test_renders_subset_of_providers() {
    local result
    printf "Z.ai zai\nClaude claude\n" > "$TMP_DIR/active_providers"
    result=$(run_status_right_force)
    assert_contains "$result" "Z.ai" "subset: Z.ai label shown"
    assert_contains "$result" "Claude" "subset: Claude label shown"
    assert_not_contains "$result" "Copilot" "subset: Copilot label hidden"
    assert_not_contains "$result" "Codex" "subset: Codex label hidden"
}

test_script_exists
test_script_syntax
test_right_script_exists
test_right_script_syntax
test_renders_all_dash_when_no_caches_forced
test_auto_hides_when_no_caches
test_exits_zero_with_no_caches
test_renders_subset_of_providers

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
test_collect_no_bare_wait
test_collect_uses_auth_json
test_collect_atomic_writes
test_collect_max_time
test_collect_no_old_llm_fuel

# ─── Section 8: OPEN_CHAD_MULTI_GAUGE toggle ─────────────────────────────────

section "OPEN_CHAD_MULTI_GAUGE toggle"

test_toggle_on_shows_dashes_with_no_caches() {
    local result
    printf "Z.ai zai\nCopilot copilot\nClaude claude\nCodex codex\n" > "$TMP_DIR/active_providers"
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_RIGHT" 2>/dev/null || true)
    assert_contains "$result" "Z.ai"    "MULTI_GAUGE=1: Z.ai shown even with no caches"
    assert_contains "$result" "Copilot" "MULTI_GAUGE=1: Copilot shown even with no caches"
    assert_contains "$result" "Claude"  "MULTI_GAUGE=1: Claude shown even with no caches"
    assert_contains "$result" "Codex"   "MULTI_GAUGE=1: Codex shown even with no caches"
}

test_collect_has_multi_gauge_toggle() {
    grep -q "_multi_gauge_enabled\|OPEN_CHAD_MULTI_GAUGE" "$COLLECT_METRICS" \
        && pass "collect_metrics.sh has OPEN_CHAD_MULTI_GAUGE support" \
        || fail "collect_metrics.sh missing OPEN_CHAD_MULTI_GAUGE toggle"
}

test_status_right_has_multi_gauge_toggle() {
    grep -q "_multi_gauge_enabled\|OPEN_CHAD_MULTI_GAUGE" "$STATUS_RIGHT" \
        && pass "status_right.sh has OPEN_CHAD_MULTI_GAUGE support" \
        || fail "status_right.sh missing OPEN_CHAD_MULTI_GAUGE toggle"
}

test_toggle_on_shows_dashes_with_no_caches
test_collect_has_multi_gauge_toggle
test_status_right_has_multi_gauge_toggle

# ─── Section 9: status_resources.sh ─────────────────────────────────────────

section "status_resources.sh"

test_resources_syntax() {
    bash -n "$STATUS_RESOURCES" 2>/dev/null \
        && pass "status_resources.sh syntax OK" \
        || fail "status_resources.sh syntax error"
}

test_resources_output_with_cache() {
    local tmp_dir result
    tmp_dir=$(mktemp -d)
    printf '42 67 1.23' > "$tmp_dir/metrics"
    result=$(OPEN_CHAD_CACHE_DIR="$tmp_dir" bash "$STATUS_RESOURCES" 2>/dev/null || true)
    rm -rf "$tmp_dir"
    assert_contains "$result" "CPU 42%"   "resources: CPU value rendered"
    assert_contains "$result" "RAM 67%"   "resources: RAM value rendered"
    assert_contains "$result" "Load 1.23" "resources: Load value rendered"
}

test_status_right_renders_session_count_before_cpu() {
    local result
    printf '42 67 1.23' > "$TMP_DIR/metrics"
    printf '3' > "$TMP_DIR/sessions"
    result=$(run_status_right_force)

    assert_contains "$result" "Sess 3" "status_right: session count rendered"
    assert_contains "$result" "CPU 42%" "status_right: CPU still rendered with session count"
}

test_status_resources_renders_session_count_when_available() {
    local tmp_dir result
    tmp_dir=$(mktemp -d)
    printf '42 67 1.23' > "$tmp_dir/metrics"
    printf '5' > "$tmp_dir/sessions"
    result=$(OPEN_CHAD_CACHE_DIR="$tmp_dir" bash "$STATUS_RESOURCES" 2>/dev/null || true)
    rm -rf "$tmp_dir"

    assert_contains "$result" "Sess 5" "resources: session count rendered when cache exists"
}

test_resources_empty_when_no_cache() {
    local tmp_dir result
    tmp_dir=$(mktemp -d)
    # No metrics file written
    result=$(OPEN_CHAD_CACHE_DIR="$tmp_dir" bash "$STATUS_RESOURCES" 2>/dev/null || true)
    rm -rf "$tmp_dir"
    assert_eq "$result" "" "resources: empty output when no cache file"
}

test_resources_uses_open_chad_cache_dir() {
    grep -q 'OPEN_CHAD_CACHE_DIR' "$STATUS_RESOURCES" \
        && pass "status_resources.sh uses OPEN_CHAD_CACHE_DIR" \
        || fail "status_resources.sh does not reference OPEN_CHAD_CACHE_DIR"
}

test_resources_sources_env() {
    grep -q 'opencode_env.sh' "$STATUS_RESOURCES" \
        && pass "status_resources.sh sources opencode_env.sh" \
        || fail "status_resources.sh does not source opencode_env.sh"
}

test_resources_reads_metrics_file() {
    grep -q 'metrics' "$STATUS_RESOURCES" \
        && pass "status_resources.sh reads metrics cache file" \
        || fail "status_resources.sh does not reference metrics file"
}

test_resources_syntax
test_resources_output_with_cache
test_status_right_renders_session_count_before_cpu
test_status_resources_renders_session_count_when_available
test_resources_empty_when_no_cache
test_resources_uses_open_chad_cache_dir
test_resources_sources_env
test_resources_reads_metrics_file

# ─── Section 10: active_providers robustness ────────────────────────────────

section "active_providers robustness"

test_malformed_active_providers_missing_key() {
    local result
    # Line with label but no cache_key — should be skipped gracefully
    printf "Z.ai zai\nOrphanLabel\nClaude claude\n" > "$TMP_DIR/active_providers"
    echo "75" > "$TMP_DIR/zai"
    echo "50" > "$TMP_DIR/claude"
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_RIGHT" 2>/dev/null || true)
    assert_contains "$result" "Z.ai"   "malformed: Z.ai still rendered"
    assert_contains "$result" "Claude"  "malformed: Claude still rendered"
    # OrphanLabel should not appear (no cache_key → skipped by [ -z "$cache_key" ] guard)
    assert_not_contains "$result" "OrphanLabel" "malformed: orphan label skipped"
}

test_active_providers_extra_whitespace() {
    local result
    # Extra trailing whitespace and blank lines
    printf "Z.ai zai  \n\n  Claude claude\n" > "$TMP_DIR/active_providers"
    echo "80" > "$TMP_DIR/zai"
    echo "60" > "$TMP_DIR/claude"
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_RIGHT" 2>/dev/null || true)
    assert_contains "$result" "Z.ai"   "whitespace: Z.ai rendered despite trailing spaces"
    assert_contains "$result" "Claude"  "whitespace: Claude rendered despite leading spaces"
}

test_end_to_end_provider_ordering() {
    local result
    # Config order: Codex first, then Z.ai — renderer should preserve this order
    printf "Codex codex\nZ.ai zai\n" > "$TMP_DIR/active_providers"
    echo "90" > "$TMP_DIR/codex"
    echo "45" > "$TMP_DIR/zai"
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" OPEN_CHAD_MULTI_GAUGE=1 bash "$STATUS_RIGHT" 2>/dev/null || true)
    # Codex should appear before Z.ai in the output
    local codex_pos zai_pos
    codex_pos=$(echo "$result" | grep -bo "Codex" | head -1 | cut -d: -f1)
    zai_pos=$(echo "$result" | grep -bo "Z.ai" | head -1 | cut -d: -f1)
    if [ -n "$codex_pos" ] && [ -n "$zai_pos" ] && [ "$codex_pos" -lt "$zai_pos" ]; then
        pass "ordering: Codex appears before Z.ai (config order preserved)"
    else
        fail "ordering: expected Codex before Z.ai, got codex_pos=$codex_pos zai_pos=$zai_pos"
    fi
}

test_malformed_active_providers_missing_key
test_active_providers_extra_whitespace
test_end_to_end_provider_ordering

# ─── Section 9: Agent-order edge palette regression ──────────────────────────
# Ensures the trailing edge of status_right.sh encodes the canonical agent
# color order: build (#59C2FF) → plan (#FFB454) → scout (#F07178) → refine (#AAD94C)

section "Agent-order edge palette (status_right.sh)"

test_edge_contains_build_blue() {
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    assert_contains "$result" "#59C2FF" "trailing edge contains build blue (#59C2FF)"
}

test_edge_contains_plan_yellow() {
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    assert_contains "$result" "#FFB454" "trailing edge contains plan yellow (#FFB454)"
}

test_edge_contains_scout_pink() {
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    assert_contains "$result" "#F07178" "trailing edge contains scout pink (#F07178)"
}

test_edge_contains_refine_green() {
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    assert_contains "$result" "#AAD94C" "trailing edge contains refine green (#AAD94C)"
}

test_edge_order_build_before_plan() {
    local result blue_pos yellow_pos
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    blue_pos=$(echo "$result" | grep -bo "#59C2FF" | tail -1 | cut -d: -f1)
    yellow_pos=$(echo "$result" | grep -bo "#FFB454" | tail -1 | cut -d: -f1)
    if [ -n "$blue_pos" ] && [ -n "$yellow_pos" ] && [ "$blue_pos" -lt "$yellow_pos" ]; then
        pass "edge order: build (#59C2FF) before plan (#FFB454)"
    else
        fail "edge order: expected build before plan (blue_pos=$blue_pos yellow_pos=$yellow_pos)"
    fi
}

test_edge_order_plan_before_scout() {
    local result yellow_pos pink_pos
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    yellow_pos=$(echo "$result" | grep -bo "#FFB454" | tail -1 | cut -d: -f1)
    pink_pos=$(echo "$result" | grep -bo "#F07178" | tail -1 | cut -d: -f1)
    if [ -n "$yellow_pos" ] && [ -n "$pink_pos" ] && [ "$yellow_pos" -lt "$pink_pos" ]; then
        pass "edge order: plan (#FFB454) before scout (#F07178)"
    else
        fail "edge order: expected plan before scout (yellow_pos=$yellow_pos pink_pos=$pink_pos)"
    fi
}

test_edge_order_scout_before_refine() {
    local result pink_pos green_pos
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    pink_pos=$(echo "$result" | grep -bo "#F07178" | tail -1 | cut -d: -f1)
    green_pos=$(echo "$result" | grep -bo "#AAD94C" | tail -1 | cut -d: -f1)
    if [ -n "$pink_pos" ] && [ -n "$green_pos" ] && [ "$pink_pos" -lt "$green_pos" ]; then
        pass "edge order: scout (#F07178) before refine (#AAD94C)"
    else
        fail "edge order: expected scout before refine (pink_pos=$pink_pos green_pos=$green_pos)"
    fi
}

test_edge_uses_block_glyph() {
    local result
    result=$(OPEN_CHAD_CACHE_DIR="$TMP_DIR" bash "$STATUS_RIGHT" 2>/dev/null)
    assert_contains "$result" "▐" "trailing edge uses ▐ block glyph"
}

test_edge_contains_build_blue
test_edge_contains_plan_yellow
test_edge_contains_scout_pink
test_edge_contains_refine_green
test_edge_order_build_before_plan
test_edge_order_plan_before_scout
test_edge_order_scout_before_refine
test_edge_uses_block_glyph

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
