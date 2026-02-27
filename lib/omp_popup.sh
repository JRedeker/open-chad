#!/usr/bin/env bash
# lib/omp_popup.sh — launch omp in a tmux popup with configurable size
# Called by the prefix+m keybinding in lib/theme.conf.
#
# Override default 80%x80% via OPEN_CHAD_OMP_POPUP_SIZE (e.g. "90%x85%").
# Format: "WxH" where W and H are tmux size specs (percent or absolute).

set -euo pipefail

sz="${OPEN_CHAD_OMP_POPUP_SIZE:-80%x80%}"
w="${sz%%x*}"
h="${sz##*x}"

exec tmux display-popup -EE -w "$w" -h "$h" omp
