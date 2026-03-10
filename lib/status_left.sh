#!/usr/bin/env bash
# open-chad: Row 1 left-side renderer
# Shows "worktree / branch" for the current pane's git repo.

set -euo pipefail

# Guard against deleted cwd (e.g., worktree removed by /adv-archive).
# tmux spawns #() commands in the pane's cwd; if that directory was deleted,
# the shell emits "getcwd: cannot access parent directories" on startup.
cd "$HOME" 2>/dev/null || cd / 2>/dev/null || true

path="${1:-}"

[ -z "$path" ] && exit 0

# Bail if the pane path no longer exists (worktree was deleted)
[ -d "$path" ] || exit 0

# Derive worktree name (basename of repo root)
worktree=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null | xargs basename 2>/dev/null) || exit 0

# Derive branch
branch=$(git -C "$path" branch --show-current 2>/dev/null) || true
[ -z "$branch" ] && branch=$(git -C "$path" rev-parse --short HEAD 2>/dev/null) || true
[ -z "$branch" ] && exit 0

theme_bg="${OPEN_CHAD_THEME_BG:-#0D1017}"
muted_fg="${OPEN_CHAD_THEME_MUTED_FG:-#626d7a}"
border_fg="${OPEN_CHAD_THEME_BORDER_FG:-#1B1F29}"
text_fg="${OPEN_CHAD_THEME_TEXT_FG:-#BFBDB6}"

printf '#[bg=%s,fg=%s]%s #[fg=%s]/ #[bold,fg=%s]%s' \
    "$theme_bg" "$muted_fg" "$worktree" "$border_fg" "$text_fg" "$branch"
