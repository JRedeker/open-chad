#!/usr/bin/env bash
# open-chad: Installation script

set -euo pipefail

C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

echo -e "${C_SAGE}Starting open-chad installation...${C_RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="$SCRIPT_DIR/bin/open-chad"

# 1. Verify dependencies
echo -n "Checking dependencies... "
if ! command -v tmux &>/dev/null; then
    echo -e "${C_CORAL}WARNING: tmux not found. open-chad will fallback to direct execution.${C_RESET}"
else
    # Simple version check (we need 3.2+ for extended keys and some format arrays)
    tmux_ver=$(tmux -V | awk '{print $2}')
    echo -n "tmux $tmux_ver found. "
fi

if ! command -v opencode &>/dev/null; then
    echo -e "${C_CORAL}WARNING: opencode not found in PATH.${C_RESET}"
else
    echo -n "opencode found. "
fi
echo -e "${C_SAGE}[OK]${C_RESET}"

# 2. Setup symlink
DEST_DIR="$HOME/.local/bin"
DEST_BIN="$DEST_DIR/open-chad"

mkdir -p "$DEST_DIR"
if [ -L "$DEST_BIN" ] || [ -f "$DEST_BIN" ]; then
    rm -f "$DEST_BIN"
fi

ln -s "$BIN_PATH" "$DEST_BIN"
echo -e "Symlinked ${C_GOLD}bin/open-chad${C_RESET} -> ${C_GOLD}$DEST_BIN${C_RESET}"

# 3. Tmux theme integration
TMUX_CONF="$HOME/.tmux.conf"
THEME_CONF="$SCRIPT_DIR/lib/theme.conf"
SOURCE_CMD="source-file $THEME_CONF"

if [ -f "$TMUX_CONF" ]; then
    if ! grep -q "$THEME_CONF" "$TMUX_CONF"; then
        echo -e "\n# OPEN-CHAD THEME\n$SOURCE_CMD" >> "$TMUX_CONF"
        echo -e "Added theme source to ${C_GOLD}$TMUX_CONF${C_RESET}"
    else
        echo -e "Theme source already present in ${C_GOLD}$TMUX_CONF${C_RESET}"
    fi
else
    echo "$SOURCE_CMD" > "$TMUX_CONF"
    echo -e "Created ${C_GOLD}$TMUX_CONF${C_RESET} with theme source"
fi

echo -e "\n${C_SAGE}Installation complete!${C_RESET}"
echo -e "Make sure ${C_GOLD}$DEST_DIR${C_RESET} is in your PATH."
echo -e "Recommended alias for your .zshrc/.bashrc:"
echo -e "  ${C_GOLD}alias oc='open-chad'${C_RESET}\n"
