#!/usr/bin/env bash
# lib/omp_popup.sh — launch omp in a tmux popup with terminal-like context
# Called by the prefix+m keybinding in lib/theme.conf.
#
# Override default 80%x80% via OPEN_CHAD_OMP_POPUP_SIZE (e.g. "90%x85%").
# Override binary path via OPEN_CHAD_OMP_BIN.
# Format: "WxH" where W and H are tmux size specs (percent or absolute).

set -euo pipefail

sz="${OPEN_CHAD_OMP_POPUP_SIZE:-80%x80%}"
w="${sz%%x*}"
h="${sz##*x}"

pane_target="${TMUX_PANE:-}"
if [ -n "$pane_target" ]; then
    popup_dir="$(tmux display-message -p -t "$pane_target" '#{pane_current_path}' 2>/dev/null || pwd)"
else
    popup_dir="$PWD"
fi

if [ -n "${OPEN_CHAD_OMP_BIN:-}" ] && [ -x "${OPEN_CHAD_OMP_BIN}" ]; then
    omp_bin="$OPEN_CHAD_OMP_BIN"
elif [ -x "$HOME/.local/bin/omp" ]; then
    omp_bin="$HOME/.local/bin/omp"
elif omp_bin="$(command -v omp 2>/dev/null)"; then
    :
else
    exec tmux display-popup -EE -d "$popup_dir" -w "$w" -h "$h" "printf '%s\n' 'openchad: omp binary not found.' 'Run: bash ~/dev/open-chad/lib/setup_omp.sh'; exit 1"
fi

shell_bin="${SHELL:-/bin/bash}"
if [ ! -x "$shell_bin" ]; then
    shell_bin="/bin/bash"
fi

printf -v launch_cmd 'exec %q' "$omp_bin"
printf -v popup_cmd '%q -lc %q' "$shell_bin" "$launch_cmd"

exec tmux display-popup -EE -d "$popup_dir" -w "$w" -h "$h" "$popup_cmd"
