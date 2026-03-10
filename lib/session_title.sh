#!/usr/bin/env bash
# open-chad: OpenCode session title renderer
# Queries the opencode SQLite DB for the active session title.
# Correlates via the tmux session launch timestamp embedded in the session name (oc-<epoch>-<pid>).
# Shows nothing if no exact match — avoids cross-session title bleed.
#
# Usage: session_title.sh <pane_current_path> <session_name>

set -euo pipefail

# Guard against deleted cwd (e.g., worktree removed by /adv-archive).
# tmux spawns #() commands in the pane's cwd; if that directory was deleted,
# the shell emits "getcwd: cannot access parent directories" on startup.
# cd to $HOME early to silence this — the script uses explicit -C paths anyway.
cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true

pane_path="${1:-}"
session_name="${2:-}"
[ -z "$pane_path" ] && exit 0

# Bail if the pane path no longer exists (worktree was deleted)
[ -d "$pane_path" ] || exit 0

db="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
[ -f "$db" ] || exit 0

# Resolve git worktree root for this pane
worktree=$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Extract launch timestamp from tmux session name (oc-<epoch_seconds>-<pid>)
launch_epoch=""
if [[ "$session_name" =~ ^oc-([0-9]+)- ]]; then
    launch_epoch="${BASH_REMATCH[1]}"
fi

title=$(python3 -c "
import sqlite3, sys

db = sqlite3.connect(sys.argv[1])
worktree = sys.argv[2]
launch_epoch = sys.argv[3]

if launch_epoch:
    # Convert seconds to milliseconds; find the first top-level session
    # created within 120s after the tmux launch (covers boot delay)
    launch_ms = int(launch_epoch) * 1000
    window_ms = launch_ms + 120_000
    row = db.execute('''
        SELECT title FROM session
        WHERE directory = ?
          AND parent_id IS NULL
          AND title IS NOT NULL AND title != ''
          AND time_created >= ? AND time_created <= ?
        ORDER BY time_created ASC
        LIMIT 1
    ''', (worktree, launch_ms, window_ms)).fetchone()
    if row:
        print(row[0])
        sys.exit(0)

# No match — show nothing rather than guess wrong
" "$db" "$worktree" "${launch_epoch:-}" 2>/dev/null) || exit 0

[ -z "$title" ] && exit 0

title_fg="${OPEN_CHAD_THEME_TITLE_FG:-#BFBDB6}"

printf '#[bold,fg=%s]%s' "$title_fg" "$title"
