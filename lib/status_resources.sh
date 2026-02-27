#!/usr/bin/env bash
# open-chad: System resources renderer for tmux status bar (Row 0 right, standalone)
# Reads CPU%, RAM%, load from $OPEN_CHAD_CACHE_DIR/metrics (written by collect_metrics.sh)
# Reads openchad tmux session count from $OPEN_CHAD_CACHE_DIR/sessions
# Output: tmux-formatted string in comment gray, matching clock/date style
# Note: status_right.sh also renders resources inline alongside LLM gauges on Row 1.
# No external tool dependencies (no jq, no curl — plain bash read)

set -euo pipefail

# Resolve cache dir consistently (XDG_RUNTIME_DIR/open-chad or /tmp/open-chad-$USER)
# shellcheck source=opencode_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/opencode_env.sh"

CACHE="${OPEN_CHAD_CACHE_DIR}/metrics"

[ -f "$CACHE" ] || exit 0

read -r cpu ram load < "$CACHE" 2>/dev/null || true

[ -z "${cpu:-}" ] && exit 0

sessions=""
SESSIONS_CACHE="${OPEN_CHAD_CACHE_DIR}/sessions"
if [ -f "$SESSIONS_CACHE" ]; then
    sessions=$(cat "$SESSIONS_CACHE" 2>/dev/null || true)
fi

if [[ "${sessions:-}" =~ ^[0-9]+$ ]]; then
    printf '#[fg=#626d7a]Sess %s #[fg=#1B1F29]│ ' "$sessions"
fi

printf '#[fg=#626d7a]CPU %s%% #[fg=#1B1F29]│ #[fg=#626d7a]RAM %s%% #[fg=#1B1F29]│ #[fg=#626d7a]Load %s' "$cpu" "$ram" "$load"
