#!/usr/bin/env bash
# open-chad: System resources renderer for tmux status-right (Row 0)
# Reads CPU%, RAM%, load from /tmp/open-chad-metrics (written by collect_metrics.sh)
# Output: tmux-formatted string in comment gray, matching clock/date style
# No external tool dependencies (no jq, no curl — plain bash read)

set -euo pipefail

CACHE="${OPEN_CHAD_CACHE_DIR:-/tmp}/open-chad-metrics"

[ -f "$CACHE" ] || exit 0

read -r cpu ram load < "$CACHE" 2>/dev/null || exit 0

[ -z "${cpu:-}" ] && exit 0

printf '#[fg=#626d7a]CPU %s%% #[fg=#1B1F29]│ #[fg=#626d7a]RAM %s%% #[fg=#1B1F29]│ #[fg=#626d7a]Load %s' "$cpu" "$ram" "$load"
