#!/usr/bin/env bash
# open-chad: Row 1 right-side renderer
# Reads cached metrics + derives git context for display
# Uses neutral text formatting + grouped ▐▐▐▐ retro edge

set -euo pipefail

path="${1:-}"

# --- Git context ---
git_info="–"
if [ -n "$path" ] && [ -d "$path/.git" ] || git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$path" branch --show-current 2>/dev/null)
    if [ -n "$branch" ]; then
        # Dirty flag
        if git -C "$path" diff --quiet HEAD 2>/dev/null && git -C "$path" diff --cached --quiet HEAD 2>/dev/null; then
            git_info="$branch"
        else
            git_info="${branch}*"
        fi
    fi
fi

# --- System metrics (from shared cache) ---
cpu="–"
ram="–"
load="–"
cache="/tmp/open-chad-metrics"
if [ -f "$cache" ]; then
    read -r cpu ram load < "$cache" 2>/dev/null || true
fi

# Format output with neutral text and dark separators, ending with the grouped retro lines
printf '#[bg=colour233,fg=colour245]%s #[fg=colour238]│ #[fg=colour245]cpu %s%% #[fg=colour238]│ #[fg=colour245]ram %s%% #[fg=colour238]│ #[fg=colour245]ld %s #[fg=colour131]▐#[fg=colour173]▐#[fg=colour186]▐#[fg=colour107]▐' "$git_info" "$cpu" "$ram" "$load"
