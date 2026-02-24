#!/usr/bin/env bash
# open-chad: Row 1 left-side renderer
# Displays per-provider LLM fuel gauges + ADV title parser output
# Format: Z.ai 62% | Copilot 81% | Claude 47% | Codex --
# Reads from cache only — no disk or DB work (fast, safe for tmux callbacks)
# No external tool dependencies in render path (no jq, no curl)

set -euo pipefail

# Cache directory (override via OPEN_CHAD_CACHE_DIR for testing)
_cache_dir="${OPEN_CHAD_CACHE_DIR:-/tmp}"

# --- Color thresholds ---
_color_for_pct() {
    local pct="$1"
    if [ "$pct" -ge 50 ]; then
        printf '#AAD94C'   # green  — ≥50%
    elif [ "$pct" -ge 20 ]; then
        printf '#E6B450'   # yellow — 20–49%
    else
        printf '#FF8F40'   # red    — <20%
    fi
}

# Render one provider segment: "Label pct%" in color, or "Label --" in gray
_render_provider() {
    local label="$1"
    local cache_file="$2"
    local val=""
    local color="#626d7a"   # comment gray — default (no data)
    local display="--"

    if [ -f "$cache_file" ]; then
        val=$(cat "$cache_file" 2>/dev/null || true)
    fi

    if [[ "${val:-}" =~ ^[0-9]+$ ]]; then
        color=$(_color_for_pct "$val")
        display="${val}%"
    fi

    printf '#[fg=%s]%s %s' "$color" "$label" "$display"
}

# --- Multi-provider gauge ---
sep='#[fg=#1B1F29] | '

gauge=$(
    _render_provider "Z.ai"    "${_cache_dir}/open-chad-zai"
    printf '%s' "$sep"
    _render_provider "Copilot" "${_cache_dir}/open-chad-copilot"
    printf '%s' "$sep"
    _render_provider "Claude"  "${_cache_dir}/open-chad-claude"
    printf '%s' "$sep"
    _render_provider "Codex"   "${_cache_dir}/open-chad-codex"
)

# --- ADV title parser ---
title="${1:-}"
title_output=""
if [ -n "$title" ]; then
    title_output=$(~/dev/open-chad/lib/title_parser.sh "$title" 2>/dev/null || true)
fi

# --- Compose output ---
printf '#[bg=#0D1017]%s' "$gauge"

if [ -n "$title_output" ]; then
    printf ' #[nobold,fg=#1B1F29]│ #[nobold]%s' "$title_output"
fi
