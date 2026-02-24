#!/usr/bin/env bash
# open-chad: Row 1 left-side renderer
# Shows "worktree / branch" for the current pane's git repo.
# Hidden when there is only one window in the session (no need to differentiate).

set -euo pipefail

path="${1:-}"
window_count="${2:-1}"

# Hide when only one window — nothing to differentiate
if [ "$window_count" -le 1 ]; then
    exit 0
fi

[ -z "$path" ] && exit 0

# Derive worktree name (basename of repo root)
worktree=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null) || exit 0

# Derive branch
branch=$(git -C "$path" branch --show-current 2>/dev/null) || true
[ -z "$branch" ] && branch=$(git -C "$path" rev-parse --short HEAD 2>/dev/null) || true
[ -z "$branch" ] && exit 0

printf '#[bg=#0D1017,fg=#626d7a]%s #[fg=#1B1F29]/ #[bold,fg=#BFBDB6]%s' "$worktree" "$branch"
