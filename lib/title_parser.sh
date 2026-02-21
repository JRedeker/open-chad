#!/usr/bin/env bash
# open-chad: ADV window title parser
# Parses "🚀 repo changeId" into structured tmux formatting

set -euo pipefail

title="${1:-}"

if [ -z "$title" ]; then
    exit 0
fi

# Split title by space
read -r -a parts <<< "$title"

if [ ${#parts[@]} -lt 3 ]; then
    printf '#[bold,fg=colour250]%s' "$title"
    exit 0
fi

emoji="${parts[0]}"
repo="${parts[1]}"
change="${parts[2]}"

# Join any remaining parts
extra=""
if [ ${#parts[@]} -gt 3 ]; then
    extra="${parts[*]:3}"
fi

state="SYS"
case "$emoji" in
    "🚀") state="ADV" ;;
    "🌍") state="WEB" ;;
    "🎤") state="VOZ" ;;
    "🌙") state="IDL" ;;
    "💬") state="CHT" ;;
    "⚙️") state="CFG" ;;
esac

# ▎ 🚀 ADV ▎ pokeedge / openChad10Retro
printf '#[fg=colour107]▎ #[fg=colour245]%s %s #[fg=colour107]▎ #[fg=colour245]%s #[fg=colour238]/ #[bold,fg=colour250]%s' "$emoji" "$state" "$repo" "$change"

if [ -n "$extra" ]; then
    printf ' #[nobold,fg=colour245]%s' "$extra"
fi
