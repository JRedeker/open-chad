#!/usr/bin/env bash
# open-chad: System resources renderer for tmux status bar (Row 0 right, standalone)
# Reads CPU%, RAM%, load from $OPEN_CHAD_CACHE_DIR/metrics (written by collect_metrics.sh)
# Reads openchad tmux session count from $OPEN_CHAD_CACHE_DIR/sessions
# Output: tmux-formatted string in comment gray, matching clock/date style
# Note: status_right.sh also renders resources inline alongside LLM gauges on Row 1.
# No external tool dependencies (no jq, no curl — plain bash read)

set -euo pipefail

# Guard against deleted cwd (e.g., worktree removed by /adv-archive).
# tmux spawns #() commands in the pane's cwd; if that directory was deleted,
# the shell emits "getcwd: cannot access parent directories" on startup.
cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true

# Resolve cache dir consistently (XDG_RUNTIME_DIR/open-chad or /tmp/open-chad-$USER)
# shellcheck source=opencode_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/opencode_env.sh"

CACHE="${OPEN_CHAD_CACHE_DIR}/metrics"
muted_fg="${OPEN_CHAD_THEME_MUTED_FG:-#BFBDB6}"
border_fg="${OPEN_CHAD_THEME_BORDER_FG:-#3A3A3A}"

[ -f "$CACHE" ] || exit 0

read -r cpu ram load < "$CACHE" 2>/dev/null || true

[ -z "${cpu:-}" ] && exit 0

sessions=""
SESSIONS_CACHE="${OPEN_CHAD_CACHE_DIR}/sessions"
if [ -f "$SESSIONS_CACHE" ]; then
    sessions=$(cat "$SESSIONS_CACHE" 2>/dev/null || true)
fi

if [[ "${sessions:-}" =~ ^[0-9]+$ ]]; then
    printf '#[fg=%s]Sess %s #[fg=%s]│ ' "$muted_fg" "$sessions" "$border_fg"
fi

printf '#[fg=%s]CPU %s%% #[fg=%s]│ #[fg=%s]RAM %s%% #[fg=%s]│ #[fg=%s]Load %s' \
    "$muted_fg" "$cpu" "$border_fg" "$muted_fg" "$ram" "$border_fg" "$muted_fg" "$load"
