#!/usr/bin/env bash
# open-chad: OpenCode session title renderer
# Queries the opencode SQLite DB for the most recently active session title
# matching the current pane's git worktree root.
#
# Usage: session_title.sh <pane_current_path>

set -euo pipefail

pane_path="${1:-}"
[ -z "$pane_path" ] && exit 0

db="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
[ -f "$db" ] || exit 0

# Resolve git worktree root for this pane
worktree=$(git -C "$pane_path" rev-parse --show-toplevel 2>/dev/null) || exit 0

# Query the most recently updated session whose directory matches the worktree root
title=$(python3 -c "
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
row = db.execute(
    'SELECT title FROM session WHERE directory = ? AND title IS NOT NULL AND title != \"\" ORDER BY time_updated DESC LIMIT 1',
    (sys.argv[2],)
).fetchone()
if row:
    print(row[0])
" "$db" "$worktree" 2>/dev/null) || exit 0

[ -z "$title" ] && exit 0

printf '#[bold,fg=#BFBDB6]%s' "$title"
