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
    printf '#[bold,fg=#BFBDB6]%s' "$title"
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
printf '#[fg=#AAD94C]▎ #[fg=#626d7a]%s %s #[fg=#AAD94C]▎ #[fg=#626d7a]%s #[fg=#1B1F29]/ #[bold,fg=#BFBDB6]%s' "$emoji" "$state" "$repo" "$change"

if [ -n "$extra" ]; then
    printf ' #[nobold,fg=#626d7a]%s' "$extra"
fi
