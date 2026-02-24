#!/usr/bin/env bash
# open-chad: Row 1 right-side renderer
# Reads cached metrics for display
# Uses neutral text formatting + grouped ▐▐▐▐ retro edge

set -euo pipefail

path="${1:-}"

# --- System metrics (from shared cache) ---
cpu="–"
ram="–"
load="–"
cache="/tmp/open-chad-metrics"
if [ -f "$cache" ]; then
    read -r cpu ram load < "$cache" 2>/dev/null || true
fi

# Format output with neutral text and dark separators, ending with the grouped ayu accent edges
printf '#[bg=#0D1017,fg=#626d7a]cpu %s%% #[fg=#1B1F29]│ #[fg=#626d7a]ram %s%% #[fg=#1B1F29]│ #[fg=#626d7a]ld %s #[fg=#FF8F40]▐#[fg=#59C2FF]▐#[fg=#E6B450]▐#[fg=#AAD94C]▐' "$cpu" "$ram" "$load"
