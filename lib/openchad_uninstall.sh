#!/usr/bin/env bash
# lib/openchad_uninstall.sh — openchad uninstall subcommand handler
#
# Removes the openchad installation:
#   - Removes managed symlinks from ~/.local/bin
#   - Removes the OPEN-CHAD THEME block from ~/.tmux.conf
#   - Removes the OPEN-CHAD PATH block from ~/.bashrc / ~/.zshrc
#
# Does NOT remove the repo directory itself (user must do that manually).
# Does NOT remove ~/.config/opencode or Claude Code configuration.
#
# Called by: bin/openchad uninstall

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_GREEN=$'\e[38;2;170;217;76m'    # #AAD94C string
C_YELLOW=$'\e[38;2;230;180;80m'   # #E6B450 accent
C_ORANGE=$'\e[38;2;255;143;64m'   # #FF8F40 keyword
C_RESET=$'\e[0m'

ok()   { echo -e "  ${C_GREEN}✓${C_RESET} $*"; }
warn() { echo -e "  ${C_YELLOW}!${C_RESET} $*"; }
step() { echo -e "${C_YELLOW}[uninstall]${C_RESET} $*"; }

# ─── Confirmation prompt ──────────────────────────────────────────────────────
if [ "${YES_MODE:-0}" != "1" ] && [ "${1:-}" != "--yes" ]; then
    echo ""
    echo "This will remove openchad symlinks and shell profile blocks."
    echo "The repo directory ($REPO_DIR) will NOT be deleted."
    echo ""
    read -r -p "Continue? [y/N] " _confirm
    case "$_confirm" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

echo ""
step "Stopping Vision MCP daemon (if running)"
if command -v vision >/dev/null 2>&1; then
    vision daemon stop >/dev/null 2>&1 || true
    ok "Vision daemon stopped (or was not running)"
else
    ok "Vision binary not found — skipping daemon stop"
fi

step "Removing managed symlinks from ~/.local/bin"

# Source the shared manifest
# shellcheck source=symlink_manifest.sh
source "$REPO_DIR/lib/symlink_manifest.sh"

DEST_DIR="$HOME/.local/bin"
for _link_name in "${!MANAGED_SYMLINKS[@]}"; do
    _link_path="$DEST_DIR/$_link_name"
    if [ -L "$_link_path" ]; then
        rm -f "$_link_path"
        ok "Removed symlink: $_link_path"
    elif [ -e "$_link_path" ]; then
        warn "Skipping non-symlink: $_link_path (remove manually if needed)"
    fi
done
unset _link_name

# Also remove legacy open-chad symlink if present
if [ -L "$DEST_DIR/open-chad" ]; then
    rm -f "$DEST_DIR/open-chad"
    ok "Removed legacy symlink: $DEST_DIR/open-chad"
fi

# ─── Remove tmux theme block ──────────────────────────────────────────────────
step "Removing tmux theme block from ~/.tmux.conf"
TMUX_CONF="$HOME/.tmux.conf"
if [ -f "$TMUX_CONF" ] && grep -q 'OPEN-CHAD THEME' "$TMUX_CONF"; then
    # Remove the OPEN-CHAD THEME block (marker line + source-file line)
    _tmp=$(mktemp)
    awk '/# OPEN-CHAD THEME/{skip=2} skip>0{skip--; next} {print}' "$TMUX_CONF" > "$_tmp"
    mv -f "$_tmp" "$TMUX_CONF"
    ok "Removed OPEN-CHAD THEME block from $TMUX_CONF"
else
    ok "No OPEN-CHAD THEME block found in $TMUX_CONF (already clean)"
fi

# ─── Remove shell profile PATH block ─────────────────────────────────────────
step "Removing OPEN-CHAD PATH block from shell profiles"
for _profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$_profile" ] && grep -q 'OPEN-CHAD' "$_profile"; then
        _tmp=$(mktemp)
        awk '/# OPEN-CHAD BEGIN/{skip=1} skip{if(/# OPEN-CHAD END/){skip=0}; next} {print}' "$_profile" > "$_tmp"
        mv -f "$_tmp" "$_profile"
        ok "Removed OPEN-CHAD block from $_profile"
    fi
done
unset _profile

echo ""
echo -e "${C_GREEN}openchad uninstalled.${C_RESET}"
echo "The repo at $REPO_DIR was not removed."
echo "To fully remove: rm -rf $REPO_DIR"
echo ""
