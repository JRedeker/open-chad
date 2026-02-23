#!/usr/bin/env bash
# open-chad: Installation script

set -euo pipefail

C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Flag parsing (manual while/case — getopts doesn't support long flags) ────
NO_ADV=0
NO_OMP=0
NO_OPENCODE_SETUP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-adv)             NO_ADV=1;             shift ;;
        --no-omp)             NO_OMP=1;             shift ;;
        --no-opencode-setup)  NO_OPENCODE_SETUP=1;  shift ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --no-adv              Skip ADV (Advance) plugin install"
            echo "  --no-omp              Skip omp (opencode-model-preferences) install"
            echo "  --no-opencode-setup   Skip all OpenCode config changes"
            echo "  --help                Show this help"
            exit 0
            ;;
        *)
            echo -e "${C_CORAL}WARNING: Unknown flag: $1${C_RESET}" >&2
            shift
            ;;
    esac
done

echo -e "${C_SAGE}Starting open-chad installation...${C_RESET}"

BIN_PATH="$SCRIPT_DIR/bin/open-chad"

# ─── 1. Verify hard dependencies ──────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    echo -e "${C_CORAL}ERROR: node is required but was not found in PATH.${C_RESET}" >&2
    echo -e "${C_CORAL}       Install Node.js: https://nodejs.org/${C_RESET}" >&2
    exit 1
fi

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

# ─── 2. Setup symlink ─────────────────────────────────────────────────────────
DEST_DIR="$HOME/.local/bin"
DEST_BIN="$DEST_DIR/open-chad"

mkdir -p "$DEST_DIR"
if [ -L "$DEST_BIN" ] || [ -f "$DEST_BIN" ]; then
    rm -f "$DEST_BIN"
fi

ln -s "$BIN_PATH" "$DEST_BIN"
echo -e "Symlinked ${C_GOLD}bin/open-chad${C_RESET} -> ${C_GOLD}$DEST_BIN${C_RESET}"

# ─── 3. Tmux theme integration ────────────────────────────────────────────────
TMUX_CONF="$HOME/.tmux.conf"
THEME_CONF="$SCRIPT_DIR/lib/theme.conf"
SOURCE_CMD="source-file $THEME_CONF"

if [ -f "$TMUX_CONF" ]; then
    if ! grep -q "$THEME_CONF" "$TMUX_CONF"; then
        printf "\n# OPEN-CHAD THEME\n%s\n" "$SOURCE_CMD" >> "$TMUX_CONF"
        echo -e "Added theme source to ${C_GOLD}$TMUX_CONF${C_RESET}"
    else
        echo -e "Theme source already present in ${C_GOLD}$TMUX_CONF${C_RESET}"
    fi
else
    echo "$SOURCE_CMD" > "$TMUX_CONF"
    echo -e "Created ${C_GOLD}$TMUX_CONF${C_RESET} with theme source"
fi

# ─── 4. ADV setup ─────────────────────────────────────────────────────────────
if [ "$NO_ADV" -eq 0 ]; then
    echo -e "\n${C_SAGE}[Step 1/3] Setting up ADV (Advance) plugin...${C_RESET}"
    bash "$SCRIPT_DIR/lib/setup_adv.sh"
else
    echo -e "${C_CORAL}Skipping ADV setup (--no-adv)${C_RESET}"
fi

# ─── 5. omp setup ─────────────────────────────────────────────────────────────
if [ "$NO_OMP" -eq 0 ]; then
    echo -e "\n${C_SAGE}[Step 2/3] Installing omp (opencode-model-preferences)...${C_RESET}"
    bash "$SCRIPT_DIR/lib/setup_omp.sh"
else
    echo -e "${C_CORAL}Skipping omp setup (--no-omp)${C_RESET}"
fi

# ─── 6. OpenCode config setup ─────────────────────────────────────────────────
if [ "$NO_OPENCODE_SETUP" -eq 0 ]; then
    echo -e "\n${C_SAGE}[Step 3/3] Configuring OpenCode environment...${C_RESET}"
    bash "$SCRIPT_DIR/lib/setup_opencode.sh"
else
    echo -e "${C_CORAL}Skipping OpenCode setup (--no-opencode-setup)${C_RESET}"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo -e "\n${C_SAGE}Installation complete!${C_RESET}"
echo -e "Make sure ${C_GOLD}$DEST_DIR${C_RESET} is in your PATH."
echo -e "Recommended alias for your .zshrc/.bashrc:"
echo -e "  ${C_GOLD}alias oc='open-chad'${C_RESET}\n"
