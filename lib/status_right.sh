#!/usr/bin/env bash
# open-chad: Row 1 right-side renderer
# Displays system resources + per-provider LLM fuel gauges as one unit.
# Format: Sess 3 | CPU 42% | RAM 67% | Load 1.23 | Z.ai 100% | Copilot 0% | Claude 89% | Codex 100% ▐▐▐▐
# Reads from cache only — no disk or DB work (fast, safe for tmux callbacks)
# No external tool dependencies in render path (no jq, no curl)
#
# Multi-provider gauge respects OPEN_CHAD_MULTI_GAUGE:
#   1 / true   → always show (all -- when no data)
#   0 / false  → never show
#   unset/auto → show only if at least one cache file has a valid value

set -euo pipefail

# Resolve dedicated cache directory (exports OPEN_CHAD_CACHE_DIR)
# shellcheck source=opencode_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/opencode_env.sh"

session_name="${1:-default}"

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
    local active_file="${OPEN_CHAD_CACHE_DIR}/active_providers"
    if [ -f "$active_file" ]; then
        while read -r _label cache_key; do
            [ -z "$cache_key" ] && continue
            local f="${OPEN_CHAD_CACHE_DIR}/${cache_key}"
            if [ -f "$f" ]; then
                local v
                v=$(cat "$f" 2>/dev/null || true)
                [[ "${v:-}" =~ ^[0-9]+$ ]] && return 0
            fi
        done < "$active_file"
    else
        # Fallback to default 4 providers
        local f
        for f in \
            "${OPEN_CHAD_CACHE_DIR}/zai" \
            "${OPEN_CHAD_CACHE_DIR}/copilot" \
            "${OPEN_CHAD_CACHE_DIR}/claude" \
            "${OPEN_CHAD_CACHE_DIR}/codex"
        do
            if [ -f "$f" ]; then
                local v
                v=$(cat "$f" 2>/dev/null || true)
                [[ "${v:-}" =~ ^[0-9]+$ ]] && return 0
            fi
        done
    fi
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

# --- System resources (CPU / RAM / Load) ---
sep='#[fg=#1B1F29] │ '

_render_resources() {
    local cache="${OPEN_CHAD_CACHE_DIR}/metrics"
    [ -f "$cache" ] || return 0
    local cpu ram load
    read -r cpu ram load < "$cache" 2>/dev/null || true
    [ -z "${cpu:-}" ] && return 0

    local sessions_cache="${OPEN_CHAD_CACHE_DIR}/sessions"
    local sessions_segment=""
    if [ -f "$sessions_cache" ]; then
        local sessions
        sessions=$(cat "$sessions_cache" 2>/dev/null || true)
        if [[ "${sessions:-}" =~ ^[0-9]+$ ]]; then
            sessions_segment="#[fg=#626d7a]Sess ${sessions}${sep}"
        fi
    fi

    printf '%s#[fg=#626d7a]CPU %s%%%s#[fg=#626d7a]RAM %s%%%s#[fg=#626d7a]Load %s' \
        "$sessions_segment" "$cpu" "$sep" "$ram" "$sep" "$load"
}

# --- Multi-provider gauge ---
_render_gauges() {
    local active_file="${OPEN_CHAD_CACHE_DIR}/active_providers"
    local first=1

    if [ -f "$active_file" ]; then
        while read -r label cache_key; do
            [ -z "$cache_key" ] && continue
            if [ "$first" -eq 0 ]; then
                printf '%s' "$sep"
            fi
            _render_provider "$label" "${OPEN_CHAD_CACHE_DIR}/${cache_key}"
            first=0
        done < "$active_file"
    else
        # Fallback to default 4 providers
        _render_provider "Z.ai"    "${OPEN_CHAD_CACHE_DIR}/zai"
        printf '%s' "$sep"
        _render_provider "Copilot" "${OPEN_CHAD_CACHE_DIR}/copilot"
        printf '%s' "$sep"
        _render_provider "Claude"  "${OPEN_CHAD_CACHE_DIR}/claude"
        printf '%s' "$sep"
        _render_provider "Codex"   "${OPEN_CHAD_CACHE_DIR}/codex"
    fi
}

# --- Compose right block as one unit ---
resources=$(_render_resources)
gauges_enabled=0
_multi_gauge_enabled && gauges_enabled=1 || true

if [ -n "$resources" ] && [ "$gauges_enabled" -eq 1 ]; then
    printf '%s%s' "$resources" "$sep"
    _render_gauges
elif [ -n "$resources" ]; then
    printf '%s' "$resources"
elif [ "$gauges_enabled" -eq 1 ]; then
    _render_gauges
fi

printf ' %s' "$("$(dirname "${BASH_SOURCE[0]}")/status_edges.sh" right row1 "$session_name")"
