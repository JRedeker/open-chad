#!/usr/bin/env bash
# open-chad: Installation script (v1.2)
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
#   2. Shell profile PATH setup (~/dev/open-chad/bin added to PATH)
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
SKIP_ZSH=0
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
        --no-omp|--skip-omp)
            NO_OMP=1
            WIZARD_EXTRA_FLAGS+=("--skip-omp")
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
        --skip-zsh|--no-zsh)
            SKIP_ZSH=1
            WIZARD_EXTRA_FLAGS+=("--skip-zsh")
            shift
            ;;
        --bundles)
            # Normalize: accept comma-separated or space-separated
            BUNDLES=$(echo "$2" | tr ',' ' ' | tr -s ' ' | xargs)
            WIZARD_EXTRA_FLAGS+=("--bundles" "$BUNDLES")
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
            echo "  --skip-zsh / --no-zsh  Skip zsh + plugin setup"
            echo "  --bundles <list>       Pre-select language bundles: 'python go rust web'"
            echo "  --verbose              Show verbose output"
            echo "  --no-env-check         Skip pre-flight environment checks"
            echo "  --help                 Show this help"
            exit 0
            ;;
        --skip-*)
            # Forward any --skip-* flags directly to wizard.sh
            WIZARD_EXTRA_FLAGS+=("$1")
            shift
            ;;
        *)
            echo -e "${C_CORAL}WARNING: Unknown flag: $1${C_RESET}" >&2
            shift
            ;;
    esac
done

echo -e "${C_SAGE}open-chad v1.2 — installer starting...${C_RESET}"

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

# ─── 3. Shell profile PATH setup ──────────────────────────────────────────────
# The shell profile is configured in lib/setup_shell_profile.sh which adds
# ~/dev/open-chad/bin to PATH. The wizard calls this, but we also call it here
# for non-interactive installs so PATH is available immediately.
step() { echo -e "${C_GOLD}[install]${C_RESET} $*"; }
step "Setting up shell profile PATH"
bash "$SCRIPT_DIR/lib/setup_shell_profile.sh" || echo -e "${C_CORAL}WARNING: Shell profile setup had issues (continuing)${C_RESET}"

# Remove stale alias oc='open-chad' and PATH from shell rc files (legacy cleanup)
_clean_stale_alias() {
    local rc_file="$1"
    [ -f "$rc_file" ] || return 0
    local changed=0
    if grep -qE "^[[:space:]]*alias[[:space:]]+oc=['\"]open-chad['\"]" "$rc_file"; then
        local tmp_file; tmp_file=$(mktemp)
        awk '
            /^[[:space:]]*#.*[Oo]pen-[Cc]had.*replaces old oc/ { next }
            /^[[:space:]]*alias[[:space:]]+oc=.open-chad/ { next }
            { print }
        ' "$rc_file" > "$tmp_file"
        mv -f "$tmp_file" "$rc_file"
        changed=1
    fi
    if [ "$changed" -eq 1 ]; then
        echo -e "Cleaned stale open-chad references from ${C_GOLD}$(basename "$rc_file")${C_RESET}"
    fi
}
_clean_stale_alias "$HOME/.zshrc"
_clean_stale_alias "$HOME/.bashrc"
_clean_stale_alias "$HOME/.bash_profile"

# ─── 4. Tmux theme integration ────────────────────────────────────────────────
TMUX_CONF="$HOME/.tmux.conf"
THEME_CONF="$SCRIPT_DIR/lib/theme.conf"
SOURCE_CMD="source-file $THEME_CONF"

if [ -f "$TMUX_CONF" ]; then
    # Check for the OPEN-CHAD THEME marker to avoid duplicate source-file lines
    if ! grep -q 'OPEN-CHAD THEME' "$TMUX_CONF"; then
        # Backup before modifying (git-safe: use .bak only in /tmp, not in repo)
        cp "$TMUX_CONF" "/tmp/tmux.conf.openchad-backup.$$" 2>/dev/null || true
        printf "\n# OPEN-CHAD THEME\n%s\n" "$SOURCE_CMD" >> "$TMUX_CONF"
        echo -e "Added theme source to ${C_GOLD}$TMUX_CONF${C_RESET}"
    else
        echo -e "Theme source already present in ${C_GOLD}$TMUX_CONF${C_RESET}"
    fi
else
    echo "$SOURCE_CMD" > "$TMUX_CONF"
    echo -e "Created ${C_GOLD}$TMUX_CONF${C_RESET} with theme source"
fi

# OMP popup availability note (theme binds prefix+m with a tmux >=3.2 guard)
if command -v tmux >/dev/null 2>&1; then
    _tmux_version_raw=$(tmux -V 2>/dev/null | awk '{print $2}')
    _tmux_major=$(printf '%s' "${_tmux_version_raw:-0}" | awk -F. '{gsub(/[^0-9]/, "", $1); print ($1==""?0:$1)}')
    _tmux_minor=$(printf '%s' "${_tmux_version_raw:-0}" | awk -F. '{gsub(/[^0-9]/, "", $2); print ($2==""?0:$2)}')

    if [ "$_tmux_major" -gt 3 ] || { [ "$_tmux_major" -eq 3 ] && [ "$_tmux_minor" -ge 2 ]; }; then
        echo -e "OMP popup keybind ${C_GOLD}prefix+m${C_RESET}: enabled (tmux ${C_GOLD}${_tmux_version_raw}${C_RESET})"
    else
        echo -e "OMP popup keybind ${C_GOLD}prefix+m${C_RESET}: tmux ${C_GOLD}${_tmux_version_raw}${C_RESET} < 3.2 (fallback message only)"
    fi
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
    [ "$NO_OPENCODE_SETUP" -eq 1 ] && WIZARD_ARGS+=("--skip-mcp" "--skip-morph" "--skip-adv")

    exec bash "$SCRIPT_DIR/lib/wizard.sh" "${WIZARD_ARGS[@]}"
fi
