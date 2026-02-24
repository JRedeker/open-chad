#!/usr/bin/env bash
# open-chad: Row 1 right-side renderer
# Displays per-provider LLM fuel gauges
# Format: Z.ai 100% | Copilot 0% | Claude 89% | Codex 100%
# Reads from cache only — no disk or DB work (fast, safe for tmux callbacks)
# No external tool dependencies in render path (no jq, no curl)
#
# Multi-provider gauge respects OPEN_CHAD_MULTI_GAUGE:
#   1 / true   → always show (all -- when no data)
#   0 / false  → never show
#   unset/auto → show only if at least one cache file has a valid value

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

# Returns 0 if at least one provider cache file has a valid integer
_has_any_gauge_data() {
    local f
    for f in \
        "${_cache_dir}/open-chad-zai" \
        "${_cache_dir}/open-chad-copilot" \
        "${_cache_dir}/open-chad-claude" \
        "${_cache_dir}/open-chad-codex"
    do
        if [ -f "$f" ]; then
            local v
            v=$(cat "$f" 2>/dev/null || true)
            [[ "${v:-}" =~ ^[0-9]+$ ]] && return 0
        fi
    done
    return 1
}

# Determine whether to render the multi-provider gauge
_multi_gauge_enabled() {
    local setting="${OPEN_CHAD_MULTI_GAUGE:-auto}"
    case "$setting" in
        1|true|yes|on)   return 0 ;;
        0|false|no|off)  return 1 ;;
        *)  # auto: only show if at least one cache has real data
            _has_any_gauge_data
            ;;
    esac
}

# --- Multi-provider gauge ---
sep='#[fg=#1B1F29] | '

if _multi_gauge_enabled; then
    _render_provider "Z.ai"    "${_cache_dir}/open-chad-zai"
    printf '%s' "$sep"
    _render_provider "Copilot" "${_cache_dir}/open-chad-copilot"
    printf '%s' "$sep"
    _render_provider "Claude"  "${_cache_dir}/open-chad-claude"
    printf '%s' "$sep"
    _render_provider "Codex"   "${_cache_dir}/open-chad-codex"
    printf ' #[fg=#FF8F40]▐#[fg=#59C2FF]▐#[fg=#E6B450]▐#[fg=#AAD94C]▐'
fi
