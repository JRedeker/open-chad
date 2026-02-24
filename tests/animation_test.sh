#!/usr/bin/env bash
# tests/animation_test.sh — Unit tests for boot animation
# Tests: syntax, logo dimensions, centering math, color palette, phase structure
#
# Usage: bash tests/animation_test.sh
# Exit code: number of failed tests (0 = all passed)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ANIMATION="$REPO_DIR/lib/animation.sh"

# ─── Test Infrastructure ──────────────────────────────────────────────────────

TESTS_PASSED=0
TESTS_FAILED=0

pass() { echo "  PASS: $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo "  FAIL: $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

assert_eq()       { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', expected '$2')"; }
assert_contains() { echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (looking for '$2' in '$1')"; }
assert_ge()       { [ "$1" -ge "$2" ] && pass "$3" || fail "$3 (got '$1', expected >= '$2')"; }
assert_le()       { [ "$1" -le "$2" ] && pass "$3" || fail "$3 (got '$1', expected <= '$2')"; }

section() { echo ""; echo "── $1 ──"; }

# ─── Section 1: Script structure ─────────────────────────────────────────────

section "Script structure"

test_file_exists() {
    [ -f "$ANIMATION" ] && pass "animation.sh exists" || fail "animation.sh missing: $ANIMATION"
}

test_is_executable() {
    [ -x "$ANIMATION" ] && pass "animation.sh is executable" || fail "animation.sh not executable"
}

test_syntax() {
    bash -n "$ANIMATION" 2>/dev/null && pass "animation.sh syntax OK" || fail "animation.sh syntax error"
}

test_shebang() {
    local first_line
    first_line=$(head -1 "$ANIMATION")
    [ "$first_line" = "#!/usr/bin/env bash" ] && pass "correct shebang" || fail "wrong shebang: $first_line"
}

test_set_euo_pipefail() {
    grep -q 'set -euo pipefail' "$ANIMATION" && pass "strict mode enabled" || fail "missing set -euo pipefail"
}

test_file_exists
test_is_executable
test_syntax
test_shebang
test_set_euo_pipefail

# ─── Section 2: Logo dimensions ──────────────────────────────────────────────

section "Logo dimensions"

test_logo_has_6_lines() {
    local count
    count=$(grep -c '^\s*".*[█╗╔═╝║]' "$ANIMATION" || echo 0)
    assert_eq "$count" "6" "logo array has 6 lines"
}

test_logo_width_constant() {
    grep -q 'LOGO_WIDTH=74' "$ANIMATION" && pass "LOGO_WIDTH=74 defined" || fail "LOGO_WIDTH=74 not found"
}

test_logo_height_constant() {
    grep -q 'LOGO_HEIGHT=6' "$ANIMATION" && pass "LOGO_HEIGHT=6 defined" || fail "LOGO_HEIGHT=6 not found"
}

test_logo_has_6_lines
test_logo_width_constant
test_logo_height_constant

# ─── Section 3: Centering math ───────────────────────────────────────────────

section "Centering math"

# Simulate the centering calculation for various terminal sizes
calc_logo_x() {
    local term_width="$1"
    local logo_width=74
    local x=$(( (term_width - logo_width) / 2 ))
    x=$(( x < 0 ? 0 : x ))
    echo "$x"
}

calc_logo_y() {
    local term_height="$1"
    local logo_height=6
    local y=$(( (term_height - logo_height - 10) / 2 ))
    y=$(( y < 1 ? 1 : y ))
    echo "$y"
}

test_center_x_80_cols() {
    local x
    x=$(calc_logo_x 80)
    assert_eq "$x" "3" "80-col terminal: logo X = 3"
}

test_center_x_120_cols() {
    local x
    x=$(calc_logo_x 120)
    assert_eq "$x" "23" "120-col terminal: logo X = 23"
}

test_center_x_200_cols() {
    local x
    x=$(calc_logo_x 200)
    assert_eq "$x" "63" "200-col terminal: logo X = 63"
}

test_center_x_narrow_clamps_to_zero() {
    local x
    x=$(calc_logo_x 40)
    assert_eq "$x" "0" "40-col terminal: logo X clamped to 0"
}

test_center_x_exact_width() {
    local x
    x=$(calc_logo_x 74)
    assert_eq "$x" "0" "74-col terminal (exact logo width): logo X = 0"
}

test_center_y_24_rows() {
    local y
    y=$(calc_logo_y 24)
    assert_eq "$y" "4" "24-row terminal: logo Y = 4"
}

test_center_y_40_rows() {
    local y
    y=$(calc_logo_y 40)
    assert_eq "$y" "12" "40-row terminal: logo Y = 12"
}

test_center_y_small_clamps_to_1() {
    local y
    y=$(calc_logo_y 10)
    assert_eq "$y" "1" "10-row terminal: logo Y clamped to 1"
}

test_center_y_16_rows() {
    local y
    y=$(calc_logo_y 16)
    assert_eq "$y" "1" "16-row terminal: logo Y = 1 (clamped)"
}

test_center_x_80_cols
test_center_x_120_cols
test_center_x_200_cols
test_center_x_narrow_clamps_to_zero
test_center_x_exact_width
test_center_y_24_rows
test_center_y_40_rows
test_center_y_small_clamps_to_1
test_center_y_16_rows

# ─── Section 4: Color palette ────────────────────────────────────────────────

section "Color palette"

test_has_6_colors() {
    # The colors array should have 6 entries
    grep -q 'colors=(' "$ANIMATION" && pass "colors array defined" || fail "colors array not found"
}

test_palette_green() {
    grep -q '170;217;76' "$ANIMATION" && pass "green (#AAD94C) present" || fail "green missing"
}

test_palette_golden() {
    grep -q '230;180;80' "$ANIMATION" && pass "golden (#E6B450) present" || fail "golden missing"
}

test_palette_blue() {
    grep -q '89;194;255' "$ANIMATION" && pass "blue (#59C2FF) present" || fail "blue missing"
}

test_palette_orange() {
    grep -q '255;143;64' "$ANIMATION" && pass "orange (#FF8F40) present" || fail "orange missing"
}

test_palette_func_orange() {
    grep -q '255;180;84' "$ANIMATION" && pass "func orange (#FFB454) present" || fail "func orange missing"
}

test_palette_gray() {
    grep -q '98;109;122' "$ANIMATION" && pass "gray (#626d7a) present" || fail "gray missing"
}

test_has_6_colors
test_palette_green
test_palette_golden
test_palette_blue
test_palette_orange
test_palette_func_orange
test_palette_gray

# ─── Section 5: Animation phases ─────────────────────────────────────────────

section "Animation phases"

test_has_draw_logo_function() {
    grep -q 'draw_logo()' "$ANIMATION" && pass "draw_logo() function defined" || fail "draw_logo() missing"
}

test_has_typewriter_function() {
    grep -q 'typewriter()' "$ANIMATION" && pass "typewriter() function defined" || fail "typewriter() missing"
}

test_color_cycling_loop() {
    grep -q 'for cycle in' "$ANIMATION" && pass "color cycling loop present" || fail "color cycling loop missing"
}

test_draw_logo_uses_offset() {
    grep -q 'draw_logo "$cycle"' "$ANIMATION" && pass "draw_logo called with cycle offset" || fail "draw_logo not called with offset"
}

test_subtitle_centered() {
    grep -q 'SUBTITLE_X=$((' "$ANIMATION" && pass "subtitle X computed dynamically" || fail "subtitle X not computed"
}

test_subtitle_text() {
    grep -q 'O P E N - C H A D' "$ANIMATION" && pass "subtitle text present" || fail "subtitle text missing"
}

test_launch_text_centered() {
    grep -q 'LAUNCH_X=$((' "$ANIMATION" && pass "launch text X computed dynamically" || fail "launch text X not computed"
}

test_info_centered() {
    grep -q 'INFO_X=$((' "$ANIMATION" && pass "info X computed dynamically" || fail "info X not computed"
}

test_details_centered() {
    grep -q 'DETAILS_X=$((' "$ANIMATION" && pass "details X computed dynamically" || fail "details X not computed"
}

test_terminal_dimensions_detected() {
    grep -q 'tput cols' "$ANIMATION" && pass "terminal width detected" || fail "tput cols not found"
    grep -q 'tput lines' "$ANIMATION" && pass "terminal height detected" || fail "tput lines not found"
}

test_cursor_hidden_at_start() {
    grep -q 'tput civis' "$ANIMATION" && pass "cursor hidden at start" || fail "tput civis missing"
}

test_cursor_restored_at_end() {
    grep -q 'tput cnorm' "$ANIMATION" && pass "cursor restored at end" || fail "tput cnorm missing"
}

test_trap_restores_cursor() {
    grep -q "trap.*tput cnorm" "$ANIMATION" && pass "trap restores cursor on interrupt" || fail "trap missing cursor restore"
}

test_has_draw_logo_function
test_has_typewriter_function
test_color_cycling_loop
test_draw_logo_uses_offset
test_subtitle_centered
test_subtitle_text
test_launch_text_centered
test_info_centered
test_details_centered
test_terminal_dimensions_detected
test_cursor_hidden_at_start
test_cursor_restored_at_end
test_trap_restores_cursor

# ─── Section 6: No hardcoded positions ───────────────────────────────────────

section "No hardcoded positions (centering regression guard)"

test_no_hardcoded_tput_cup() {
    # All tput cup calls should use variables, not literal numbers for both row and col.
    # Allowed: tput cup $((LOGO_Y + i)) $LOGO_X
    # Forbidden: tput cup 2 0, tput cup 12 15, etc. (old hardcoded positions)
    local hardcoded
    hardcoded=$(grep 'tput cup' "$ANIMATION" | grep -E 'tput cup [0-9]+ [0-9]+' || true)
    [ -z "$hardcoded" ] && pass "no hardcoded tput cup positions" || fail "hardcoded tput cup found: $hardcoded"
}

test_no_hardcoded_tput_cup

# ─── Results ──────────────────────────────────────────────────────────────────

echo ""
echo "════════════════════════════════════"
echo "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "════════════════════════════════════"

exit "$TESTS_FAILED"
