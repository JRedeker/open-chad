#!/usr/bin/env bash
# lib/pane_border.sh — per-session randomized pane border renderer
#
# Picks a color from the agent palette and a decorative line pattern based on
# the session name hash (same djb2 technique as status_edges.sh). Each session
# gets a consistent color+pattern that persists for its lifetime.
#
# The script renders a full-width decorative line with the repo name centered.
# Line patterns include gaps, dashes, dots, and mixed segments for visual
# variety across sessions.
#
# Usage: pane_border.sh <pane_current_path> <session_name> <pane_active> <pane_width>
#   pane_active: 1 = active pane, 0 = inactive pane

set -euo pipefail

# Guard against deleted cwd (e.g., worktree removed by /adv-archive).
cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true

pane_path="${1:-}"
session_name="${2:-default}"
pane_active="${3:-0}"
pane_width="${4:-120}"
border_fg="${OPEN_CHAD_THEME_BORDER_FG:-#1B1F29}"

# Resolve repo name (shared by active and inactive paths)
repo_name=""
if [ -n "$pane_path" ] && [ -d "$pane_path" ]; then
    repo_name="$(basename "$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null | tr '[:lower:]' '[:upper:]')"
fi

# --- Inactive pane: dim, no decoration ---
if [ "$pane_active" != "1" ]; then
    printf '#[fg=%s]   %s   ' "$border_fg" "$repo_name"
    exit 0
fi

# --- Active pane: randomized color + full-width decorative line ---

PALETTE_FILE="$(dirname "${BASH_SOURCE[0]}")/agent_palette.sh"
if [ -f "$PALETTE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$PALETTE_FILE"
fi

# Agent palette colors
colors=(
    "${OPEN_CHAD_COLOR_BUILD:-#59C2FF}"    # blue
    "${OPEN_CHAD_COLOR_PLAN:-#FFB454}"     # yellow
    "${OPEN_CHAD_COLOR_SCOUT:-#F07178}"    # pink
    "${OPEN_CHAD_COLOR_REFINE:-#AAD94C}"   # green
)

# Line segment patterns — each is a repeating unit that fills the border.
# Mix of solid runs, gaps (spaces), dots, and dashes for visual variety.
# Patterns are defined as arrays of segment strings that get repeated to fill width.
#
# Key: ─ = solid line, · = dot, ╌ = dashed, (space) = gap
line_patterns=(
    "── ── ── "          # classic dash-gap
    "─── ─── "           # longer dashes, single gap
    "──── ──── "         # long dash, single gap
    "── ─ ── ─ "         # alternating long-short
    "─·─·─· "            # dot-dash
    "─── · ─── · "       # long dash, dot, gap
    "── ── ── ── ── "    # tight dash-gap
    "─ · · ─ · · "       # morse-like
    "───── ── ───── ── " # mixed lengths
    "─╌─╌─╌ "            # solid-dashed alternating
    "── · ── · ── · "    # dash-dot-dash
    "─────── ─ "         # long run, short blip
    "── ──── ── "        # short-long-short
    "─ ─ ─ ─ "           # evenly spaced singles
    "──── · · ──── "     # long dash, double dot
    "─── ── ─ "          # descending lengths
)

# Derive a numeric seed from a string (djb2-inspired hash, same as status_edges.sh)
_hash_string() {
    local input="$1"
    local i ch ord seed=5381

    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        printf -v ord '%d' "'${ch}"
        seed=$(( (seed * 33 + ord) % 2147483647 ))
    done

    printf '%s' "$seed"
}

# Build a line of exactly $1 visible characters by repeating a pattern string.
_fill_pattern() {
    local width="$1"
    local pattern="$2"
    local result="" plen=${#pattern}

    while (( ${#result} < width )); do
        result+="$pattern"
    done

    printf '%s' "${result:0:$width}"
}

seed=$(_hash_string "$session_name")
color_idx=$(( seed % ${#colors[@]} ))
pattern_idx=$(( (seed / ${#colors[@]}) % ${#line_patterns[@]} ))

color="${colors[$color_idx]}"
pattern="${line_patterns[$pattern_idx]}"

# Layout: [pad][left_line] REPO_NAME [right_line][pad]
# Center the repo name with 1-char space padding on each side
label=" ${repo_name} "
label_len=${#label}

# Total available width for line segments (subtract label + 2 outer padding chars)
line_space=$(( pane_width - label_len - 2 ))
if (( line_space < 4 )); then
    # Too narrow for decoration — just show the name
    printf '#[fg=%s] %s ' "$color" "$repo_name"
    exit 0
fi

left_len=$(( line_space / 2 ))
right_len=$(( line_space - left_len ))

left_line=$(_fill_pattern "$left_len" "$pattern")
right_line=$(_fill_pattern "$right_len" "$pattern")

printf '#[fg=%s] %s%s%s ' "$color" "$left_line" "$label" "$right_line"
