#!/usr/bin/env bash
# open-chad: Installation script (v1.0)
#
# Usage:
#   bash install.sh                    — interactive wizard (TTY detected)
#   bash install.sh --yes              — non-interactive, accept all defaults
#   bash install.sh --no-adv           — skip ADV plugin
#   bash install.sh --no-omp           — skip omp (model preferences)
#   bash install.sh --bundles "python" — pre-select language bundles
#
# What it does:
#   1. Pre-flight environment checks (Ubuntu/Debian, git, disk space)
#   2. Symlink bin/open-chad -> ~/.local/bin/open-chad
#   3. Tmux theme integration -> ~/.tmux.conf
#   4. Delegate to lib/wizard.sh (interactive) or run silently (--yes/no-TTY)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

# ─── Flag parsing ─────────────────────────────────────────────────────────────
YES_MODE=0
NO_ADV=0
NO_OMP=0
NO_OPENCODE_SETUP=0
NO_ENV_CHECK=0
BUNDLES=""
WIZARD_EXTRA_FLAGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)
            YES_MODE=1
            WIZARD_EXTRA_FLAGS+=("--yes")
            shift
            ;;
        --no-adv)
            NO_ADV=1
            WIZARD_EXTRA_FLAGS+=("--skip-adv")
            shift
            ;;
        --no-omp)
            NO_OMP=1
            shift
            ;;
        --no-opencode-setup)
            NO_OPENCODE_SETUP=1
            shift
            ;;
        --no-env-check)
            NO_ENV_CHECK=1
            shift
            ;;
        --bundles)
            BUNDLES="$2"
            WIZARD_EXTRA_FLAGS+=("--bundles" "$2")
            shift 2
            ;;
        --verbose)
            WIZARD_EXTRA_FLAGS+=("--verbose")
            shift
            ;;
        --help|-h)
            echo "Usage: install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --yes / -y             Non-interactive mode (accept all defaults)"
            echo "  --no-adv               Skip ADV (Advance) plugin install"
            echo "  --no-omp               Skip omp (opencode-model-preferences) install"
            echo "  --no-opencode-setup    Skip all OpenCode config changes"
            echo "  --bundles <list>       Pre-select language bundles: 'python go rust'"
            echo "  --verbose              Show verbose output"
            echo "  --no-env-check         Skip pre-flight environment checks"
            echo "  --help                 Show this help"
            exit 0
            ;;
        *)
            echo -e "${C_CORAL}WARNING: Unknown flag: $1${C_RESET}" >&2
            shift
            ;;
    esac
done

echo -e "${C_SAGE}open-chad v1.0 — installer starting...${C_RESET}"

# ─── 0. Set up dedicated cache directory ──────────────────────────────────────
# Creates $OPEN_CHAD_CACHE_DIR (XDG_RUNTIME_DIR/open-chad or /tmp/open-chad-$USER)
# with owner-only (0700) permissions. Safe to run before OpenCode is launched.
source "$SCRIPT_DIR/lib/opencode_env.sh"
echo -e "Cache directory: ${C_GOLD}$OPEN_CHAD_CACHE_DIR${C_RESET}"

# ─── 1. Pre-flight checks ─────────────────────────────────────────────────────
if [ "$NO_ENV_CHECK" -eq 0 ]; then
    echo ""
    if ! bash "$SCRIPT_DIR/lib/check_environment.sh"; then
        echo -e "${C_CORAL}Pre-flight checks failed. Fix the issues above and re-run install.sh${C_RESET}" >&2
        exit 1
    fi
fi

# ─── 2. Node.js check (hard dependency for json_merge.sh) ────────────────────
if ! command -v node &>/dev/null; then
    echo -e "${C_CORAL}ERROR: node is required but was not found in PATH.${C_RESET}" >&2
    echo -e "${C_CORAL}       Run first: bash lib/setup_ubuntu_deps.sh${C_RESET}" >&2
    echo -e "${C_CORAL}       Or:  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -${C_RESET}" >&2
    exit 1
fi

# ─── 3. Setup symlink ─────────────────────────────────────────────────────────
BIN_PATH="$SCRIPT_DIR/bin/open-chad"
DEST_DIR="$HOME/.local/bin"
DEST_BIN="$DEST_DIR/open-chad"

mkdir -p "$DEST_DIR"
if [ -L "$DEST_BIN" ] || [ -f "$DEST_BIN" ]; then
    rm -f "$DEST_BIN"
fi
ln -s "$BIN_PATH" "$DEST_BIN"
echo -e "Symlinked ${C_GOLD}bin/open-chad${C_RESET} -> ${C_GOLD}$DEST_BIN${C_RESET}"

# ─── 4. Tmux theme integration ────────────────────────────────────────────────
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

# ─── 5. Route to wizard or silent mode ────────────────────────────────────────
echo ""

# Determine if we have a TTY and should run the interactive wizard
_has_tty=0
[ -t 0 ] && [ -t 1 ] && _has_tty=1

if [ "$_has_tty" -eq 1 ] && [ "$YES_MODE" -eq 0 ]; then
    # Interactive TTY: run the full wizard
    echo -e "${C_SAGE}Starting interactive installation wizard...${C_RESET}"
    echo ""
    exec bash "$SCRIPT_DIR/lib/wizard.sh" "${WIZARD_EXTRA_FLAGS[@]}"
else
    # Non-interactive (--yes or piped): run silently with defaults
    if [ "$YES_MODE" -eq 0 ]; then
        echo -e "${C_GOLD}No TTY detected — running in non-interactive mode.${C_RESET}"
    fi

    WIZARD_ARGS=("--yes")
    WIZARD_ARGS+=("${WIZARD_EXTRA_FLAGS[@]}")

    # Apply legacy --no-* flags that weren't already in WIZARD_EXTRA_FLAGS
    [ "$NO_ADV" -eq 1 ]            && WIZARD_ARGS+=("--skip-adv")
    [ "$NO_OPENCODE_SETUP" -eq 1 ] && WIZARD_ARGS+=("--skip-mcp" "--skip-morph")

    exec bash "$SCRIPT_DIR/lib/wizard.sh" "${WIZARD_ARGS[@]}"
fi
