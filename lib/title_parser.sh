#!/usr/bin/env bash
# open-chad: ADV window title parser
# Parses "🚀 repo changeId" into structured tmux formatting
# Also handles bare "EMOJI Words..." tab titles from ADV sub-agents

set -euo pipefail

title="${1:-}"

if [ -z "$title" ]; then
    exit 0
fi

# Split title by space
read -r -a parts <<< "$title"

emoji="${parts[0]}"

state="SYS"
case "$emoji" in
    "🚀") state="ADV" ;;
    "🌍") state="WEB" ;;
    "🎤") state="VOZ" ;;
    "🌙") state="IDL" ;;
    "💬") state="CHT" ;;
    "⚙️") state="CFG" ;;
    "📡") state="AGT" ;;
    "🔴") state="RED" ;;
    "🟢") state="GRN" ;;
    "💀") state="ERR" ;;
esac

if [ ${#parts[@]} -lt 2 ]; then
    # No label at all — just show raw title
    printf '#[bold,fg=#BFBDB6]%s' "$title"
    exit 0
fi

if [ ${#parts[@]} -eq 2 ]; then
    # "EMOJI Word" — single label, no repo/change split
    printf '#[fg=#AAD94C]▎ #[fg=#BFBDB6]%s %s #[fg=#AAD94C]▎ #[bold,fg=#BFBDB6]%s' "$emoji" "$state" "${parts[1]}"
    exit 0
fi

# 3+ parts: check if this looks like "EMOJI repo changeId" (3 parts, part[2] looks like camelCase/kebab)
# vs "EMOJI Multi Word Label" (3+ parts that are all plain words — ADV normalized title)
# Heuristic: if part[2] contains uppercase or hyphen it's likely a changeId; otherwise treat all
# parts[1..] as a multi-word label.
repo="${parts[1]}"
change="${parts[2]}"
extra=""
if [ ${#parts[@]} -gt 3 ]; then
    extra="${parts[*]:3}"
fi

# If repo looks like a plain lowercase word and change also plain, treat whole thing as a label
if [[ "$repo" =~ ^[A-Z] ]] || [ ${#parts[@]} -gt 3 ]; then
    # Multi-word label: "EMOJI Multi Word Label" → ▎ 📡 AGT ▎ Multi Provider Gauge
    label="${parts[*]:1}"
    printf '#[fg=#AAD94C]▎ #[fg=#BFBDB6]%s %s #[fg=#AAD94C]▎ #[bold,fg=#BFBDB6]%s' "$emoji" "$state" "$label"
    exit 0
fi

# Standard: "EMOJI repo changeId" → ▎ 🚀 ADV ▎ repo / changeId
printf '#[fg=#AAD94C]▎ #[fg=#BFBDB6]%s %s #[fg=#AAD94C]▎ #[fg=#BFBDB6]%s #[fg=#3A3A3A]/ #[bold,fg=#BFBDB6]%s' "$emoji" "$state" "$repo" "$change"

if [ -n "$extra" ]; then
    printf ' #[nobold,fg=#BFBDB6]%s' "$extra"
fi
