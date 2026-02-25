#!/usr/bin/env bash
# lib/setup_shell_profile.sh — Idempotent shell profile PATH wiring
#
# Detects the active shell ($SHELL), writes a marker-guarded PATH export block
# to the appropriate rc file (~/.zshrc for zsh, ~/.bashrc for bash), and prints
# the exact reload command for the detected shell.
#
# Idempotency: uses # BEGIN open-chad / # END open-chad markers. Re-running
# this script never duplicates the block.
#
# Fallback: if the target rc file doesn't exist, falls back to ~/.profile.
# If ~/.profile also doesn't exist, it is created.
#
# Environment overrides:
#   SHELL                — detected shell (default: $SHELL from environment)
#   HOME                 — home directory (default: $HOME)
#
# Called by:
#   wizard.sh            — after deps step, before wizard steps
#   update.sh            — post-pull profile repair tip
#   check_environment.sh — auto-fix PATH warning
#   setup_dev_bundle.sh  — replaces inline Go PATH write loop
#
# Exit codes:
#   0 — Profile written (or already up to date)
#   1 — Could not determine a writable profile file

set -uo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

ok()   { echo -e "${C_SAGE}[profile] OK:${C_RESET} $*"; }
info() { echo -e "${C_GOLD}[profile]${C_RESET} $*"; }
warn() { echo -e "${C_CORAL}[profile] WARN:${C_RESET} $*"; }

# ─── Detect target rc file ────────────────────────────────────────────────────

_detected_shell="${SHELL:-/bin/bash}"
_shell_name="$(basename "$_detected_shell")"

case "$_shell_name" in
    zsh)
        _rc_file="$HOME/.zshrc"
        _reload_cmd="source ~/.zshrc"
        ;;
    bash)
        _rc_file="$HOME/.bashrc"
        _reload_cmd="source ~/.bashrc"
        ;;
    *)
        # Unknown shell — fall back to .profile
        _rc_file="$HOME/.profile"
        _reload_cmd="source ~/.profile"
        ;;
esac

# If the target rc file doesn't exist, fall back to .profile
if [ ! -f "$_rc_file" ]; then
    _rc_file="$HOME/.profile"
    _reload_cmd="source ~/.profile"
fi

# ─── Check if block already present (idempotency guard) ──────────────────────

if grep -qF "# BEGIN open-chad" "$_rc_file" 2>/dev/null; then
    ok "Shell profile already configured: $_rc_file"
    info "Reload with:  $_reload_cmd"
    exit 0
fi

# ─── Write the PATH block ─────────────────────────────────────────────────────

info "Writing PATH block to $_rc_file"

cat >> "$_rc_file" <<'EOF'

# BEGIN open-chad
# Added by open-chad installer — https://github.com/JRedeker/open-chad
export PATH="$HOME/.local/bin:$PATH"
# END open-chad
EOF

ok "PATH block written to $_rc_file"
info "Reload with:  $_reload_cmd"
