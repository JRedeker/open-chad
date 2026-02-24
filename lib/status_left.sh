#!/usr/bin/env bash
# open-chad: Row 1 left-side renderer
# Displays ⛽ fuel gauge (from LLM token cache) + ADV title parser output
# Reads from cache only — no disk or DB work (fast, safe for tmux callbacks)

set -euo pipefail

# --- LLM fuel gauge ---
llm_cache="/tmp/open-chad-llm-metrics"
fuel="–"
fuel_color="#626d7a"   # comment gray — default (no data)

if [ -f "$llm_cache" ]; then
    fuel=$(cat "$llm_cache" 2>/dev/null || echo "–")
    # Validate it's an integer before applying thresholds
    if [[ "$fuel" =~ ^[0-9]+$ ]]; then
        if [ "$fuel" -ge 50 ]; then
            fuel_color="#AAD94C"   # green  — ≥50%
        elif [ "$fuel" -ge 20 ]; then
            fuel_color="#E6B450"   # yellow — 20–49%
        else
            fuel_color="#FF8F40"   # red    — <20%
        fi
        fuel="${fuel}%"
    else
        fuel="–"
    fi
fi

# --- ADV title parser ---
title="${1:-}"
title_output=""
if [ -n "$title" ]; then
    title_output=$(~/dev/open-chad/lib/title_parser.sh "$title" 2>/dev/null || true)
fi

# --- Compose output ---
# Format: ⛽ <pct>% ░ <title_parser_output>
printf '#[bg=#0D1017,fg=%s]⛽ %s' "$fuel_color" "$fuel"

if [ -n "$title_output" ]; then
    printf ' #[nobold,fg=#1B1F29]│ #[nobold]%s' "$title_output"
fi
