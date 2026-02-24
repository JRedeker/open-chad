#!/usr/bin/env bash
# open-chad: Row 1 left-side renderer
# Displays ADV title parser output (EMOJI REPO CHANGE_ID structured zones)

set -euo pipefail

title="${1:-}"
if [ -n "$title" ]; then
    out=$(~/dev/open-chad/lib/title_parser.sh "$title" 2>/dev/null || true)
    [ -n "$out" ] && printf '#[bg=#0D1017,nobold]%s' "$out"
fi
