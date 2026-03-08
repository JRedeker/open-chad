#!/usr/bin/env bash
# lib/openchad_restart.sh — openchad restart subcommand handler
#
# Restarts OpenCode in the current openchad tmux pane so config/model
# preference changes load immediately without creating a new session.
#
# Mechanism: tmux respawn-pane -k (kills existing process, respawns in-place)
# Preserves: pane, session, window, cwd
# Does NOT: create a new tmux session, relaunch openchad (would nest tmux)
#
# Guards:
#   1. Must be inside a tmux session (TMUX set)
#   2. Must have TMUX_PANE set (identifies the target pane)
#   3. Session name must match oc-* (openchad session)
#
# Called by: bin/openchad restart

set -euo pipefail

# ─── Guard 1: Must be inside tmux ────────────────────────────────────────────

if [ -z "${TMUX:-}" ]; then
    echo "ERROR: not inside a tmux session — restart requires an active openchad session." >&2
    echo "       Launch with: openchad [project-dir]" >&2
    exit 1
fi

# ─── Guard 2: Must have TMUX_PANE ────────────────────────────────────────────

if [ -z "${TMUX_PANE:-}" ]; then
    echo "ERROR: TMUX_PANE is not set — cannot identify the target pane." >&2
    echo "       This usually means the script was not invoked from within a tmux pane." >&2
    exit 1
fi

# ─── Guard 3: Session name must be oc-* ──────────────────────────────────────

session_name="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null || echo "")"

if [[ "$session_name" != oc-* ]]; then
    echo "ERROR: not an openchad session (expected oc-* prefix, got '${session_name}')." >&2
    echo "       The restart command only works inside openchad sessions." >&2
    exit 1
fi

# ─── Resolve cwd ─────────────────────────────────────────────────────────────
# Mirror the safe-cwd fallback chain from bin/openchad:
#   pane_current_path → $PWD → $HOME → /

pane_cwd="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null || echo "")"

_resolve_restart_cwd() {
    local candidate
    for candidate in "$pane_cwd" "$PWD" "$HOME" "/"; do
        if [ -n "$candidate" ] && [ -d "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    printf '/'
}

restart_cwd="$(_resolve_restart_cwd)"

# ─── Restart via respawn-pane ─────────────────────────────────────────────────
# -k  kills the existing process in the pane before respawning
# -t  targets the current pane (TMUX_PANE)
# -c  sets the working directory for the new process

exec tmux respawn-pane -k -t "$TMUX_PANE" -c "$restart_cwd" "opencode"
