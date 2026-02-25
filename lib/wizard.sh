#!/usr/bin/env bash
# lib/wizard.sh — open-chad interactive installation wizard
#
# A step-by-step interactive wizard for first-time Ubuntu installs.
# Guides the user through: system deps, MCP servers, plugins, dev bundles,
# Claude OAuth, and Windows Terminal keybindings.
#
# Flags:
#   --yes / -y       Non-interactive mode: accept all defaults, no prompts
#   --verbose        Echo log entries to stdout as well as log file
#   --skip-deps      Skip apt dependency step
#   --skip-mcp       Skip MCP server wiring
#   --skip-morph     Skip morph-fast-apply plugin install
#   --skip-adv       Skip ADV plugin install
#   --skip-auth      Skip Claude OAuth step
#   --skip-bundles   Skip dev bundle selection
#   --bundles <list> Pre-select bundles (space-separated: "python go rust")
#
# Environment overrides:
#   OPEN_CHAD_CONFIG_FILE  — open-chad.json path
#   OPEN_CHAD_INSTALL_LOG  — log file path
#   OPENCODE_CONFIG_DIR    — opencode config dir
#
# Exit codes:
#   0 — Installation complete
#   1 — Critical failure (see log for details)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors (ayu-dark) ────────────────────────────────────────────────────────
C_STRING=$'\e[38;2;170;217;76m'    # green
C_ACCENT=$'\e[38;2;230;180;80m'    # golden yellow
C_TYPE=$'\e[38;2;89;194;255m'      # blue
C_KEYWORD=$'\e[38;2;255;143;64m'   # orange
C_COMMENT=$'\e[38;2;98;109;122m'   # gray
C_FG=$'\e[38;2;191;189;182m'       # foreground
C_RESET=$'\e[0m'

# ─── Configuration ────────────────────────────────────────────────────────────
OPEN_CHAD_CONFIG_FILE="${OPEN_CHAD_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json}"
OPEN_CHAD_INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad-install.log}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

# ─── Flag defaults ────────────────────────────────────────────────────────────
YES_MODE=0
VERBOSE=0
SKIP_DEPS=0
SKIP_MCP=0
SKIP_MORPH=0
SKIP_ADV=0
SKIP_AUTH=0
SKIP_BUNDLES=0
PRESELECT_BUNDLES=""

# ─── Flag parsing ─────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes|-y)            YES_MODE=1;                   shift ;;
        --verbose)           VERBOSE=1;                    shift ;;
        --skip-deps)         SKIP_DEPS=1;                  shift ;;
        --skip-mcp)          SKIP_MCP=1;                   shift ;;
        --skip-morph)        SKIP_MORPH=1;                 shift ;;
        --skip-adv)          SKIP_ADV=1;                   shift ;;
        --skip-auth)         SKIP_AUTH=1;                  shift ;;
        --skip-bundles)      SKIP_BUNDLES=1;               shift ;;
        --bundles)           PRESELECT_BUNDLES="$2";       shift 2 ;;
        --help|-h)
            echo "Usage: bash lib/wizard.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --yes / -y          Non-interactive (accept defaults)"
            echo "  --verbose           Echo log to stdout"
            echo "  --skip-deps         Skip apt dependencies"
            echo "  --skip-mcp          Skip MCP server config"
            echo "  --skip-morph        Skip morph-fast-apply install"
            echo "  --skip-adv          Skip ADV install"
            echo "  --skip-auth         Skip Claude OAuth step"
            echo "  --skip-bundles      Skip dev bundle selection"
            echo "  --bundles <list>    Pre-select bundles (e.g. 'python go')"
            exit 0
            ;;
        *) shift ;;
    esac
done

# ─── Logging ──────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$OPEN_CHAD_INSTALL_LOG")"
touch "$OPEN_CHAD_INSTALL_LOG"
chmod 0600 "$OPEN_CHAD_INSTALL_LOG"

_log() {
    local msg="[$(date -Iseconds)] $*"
    echo "$msg" >> "$OPEN_CHAD_INSTALL_LOG"
    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${C_COMMENT}$msg${C_RESET}"
    fi
}

_log_flush() {
    # Sync log to disk for readability (no-op on Linux but good habit)
    sync 2>/dev/null || true
}

# ─── Step display ─────────────────────────────────────────────────────────────
_step_banner() {
    local step_num="$1"
    local total="$2"
    local title="$3"
    echo ""
    echo -e "${C_STRING}╔══════════════════════════════════════════════════════╗${C_RESET}"
    printf "${C_STRING}║${C_RESET} ${C_ACCENT}Step %s/%s:${C_RESET} %-43s${C_STRING}║${C_RESET}\n" "$step_num" "$total" "$title"
    echo -e "${C_STRING}╚══════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
    _log "STEP $step_num/$total: $title"
}

ok()    { echo -e "  ${C_STRING}✓${C_RESET} $*"; _log "OK: $*"; }
warn()  { echo -e "  ${C_KEYWORD}⚠${C_RESET} $*"; _log "WARN: $*"; }
info()  { echo -e "  ${C_COMMENT}·${C_RESET} $*"; }
skip()  { echo -e "  ${C_COMMENT}–${C_RESET} ${C_COMMENT}skipped: $*${C_RESET}"; _log "SKIP: $*"; }

# ─── Prompt helpers ───────────────────────────────────────────────────────────
_confirm() {
    local prompt="$1"
    local default="${2:-y}"  # y or n
    if [ "$YES_MODE" -eq 1 ]; then
        _log "AUTO-CONFIRM (--yes): $prompt → $default"
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    local yn_prompt
    if [[ "$default" == "y" ]]; then
        yn_prompt="[Y/n]"
    else
        yn_prompt="[y/N]"
    fi
    echo -ne "  ${C_ACCENT}?${C_RESET} ${prompt} ${C_COMMENT}${yn_prompt}${C_RESET} "
    local answer
    read -r answer
    answer="${answer:-$default}"
    _log "CONFIRM: $prompt → $answer"
    [[ "$answer" =~ ^[Yy] ]]
}

_multiselect() {
    local prompt="$1"
    shift
    local options=("$@")
    local selected=()

    if [ "$YES_MODE" -eq 1 ]; then
        _log "AUTO-SELECT (--yes): all options: ${options[*]}"
        echo "${options[*]}"
        return 0
    fi

    echo -e "  ${C_ACCENT}Select bundles to install:${C_RESET} (space to toggle, Enter to confirm)"
    echo -e "  ${C_COMMENT}Type the numbers separated by spaces, e.g. '1 2' for Python and Go:${C_RESET}"
    echo ""
    for i in "${!options[@]}"; do
        echo -e "    ${C_TYPE}[$((i+1))]${C_RESET} ${options[$i]}"
    done
    echo -e "    ${C_COMMENT}[0]${C_RESET} None (skip all bundles)"
    echo ""
    echo -ne "  ${C_ACCENT}?${C_RESET} Your selection: "
    local answer
    read -r answer
    _log "BUNDLE SELECTION INPUT: $answer"

    if [[ "$answer" == "0" ]] || [[ -z "$answer" ]]; then
        _log "BUNDLES SELECTED: (none)"
        echo ""
        return 0
    fi

    for num in $answer; do
        local idx=$((num - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#options[@]}" ]; then
            selected+=("${options[$idx]}")
        fi
    done

    _log "BUNDLES SELECTED: ${selected[*]:-none}"
    echo "${selected[*]:-}"
}

# ─── Welcome banner ───────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo ""
echo -e "${C_STRING}  ╔═══════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_STRING}  ║${C_RESET}     ${C_ACCENT}open-chad v1.0 — Installation Wizard${C_RESET}     ${C_STRING}║${C_RESET}"
echo -e "${C_STRING}  ╚═══════════════════════════════════════════════╝${C_RESET}"
echo ""
echo -e "  ${C_FG}This wizard installs open-chad and configures OpenCode${C_RESET}"
echo -e "  ${C_FG}for your development environment.${C_RESET}"
echo ""
echo -e "  ${C_COMMENT}Install log: $OPEN_CHAD_INSTALL_LOG${C_RESET}"
if [ "$YES_MODE" -eq 1 ]; then
    echo -e "  ${C_COMMENT}Running in non-interactive mode (--yes)${C_RESET}"
fi
echo ""

_log "=== open-chad wizard start $(date -Iseconds) ==="
_log "YES_MODE=$YES_MODE VERBOSE=$VERBOSE"
_log "CONFIG=$OPEN_CHAD_CONFIG_FILE"
_log_flush

TOTAL_STEPS=7

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1: System Dependencies
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 1 "$TOTAL_STEPS" "System Dependencies"

if [ "$SKIP_DEPS" -eq 1 ]; then
    skip "apt dependencies (--skip-deps)"
else
    info "Installing core system packages (git, curl, tmux, node, pnpm)..."
    info "This may take 1-2 minutes. Output redirected to: $OPEN_CHAD_INSTALL_LOG"
    echo ""
    OPEN_CHAD_BUNDLES="" \
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
        bash "$REPO_DIR/lib/setup_ubuntu_deps.sh" || {
        warn "Dependency install had errors. Check: $OPEN_CHAD_INSTALL_LOG"
    }
    ok "Core dependencies installed"
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2: Claude OAuth Authentication
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 2 "$TOTAL_STEPS" "Claude Authentication"

if [ "$SKIP_AUTH" -eq 1 ]; then
    skip "Claude OAuth (--skip-auth)"
else
    _no_wait_flag=""
    [ "$YES_MODE" -eq 1 ] && _no_wait_flag="--no-wait"
    OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
        bash "$REPO_DIR/lib/setup_opencode_auth.sh" $_no_wait_flag
    _log "AUTH STEP COMPLETE"
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3: Dev Language Bundles
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 3 "$TOTAL_STEPS" "Developer Language Bundles"

SELECTED_BUNDLES=""

if [ "$SKIP_BUNDLES" -eq 1 ]; then
    skip "dev bundles (--skip-bundles)"
elif [ -n "$PRESELECT_BUNDLES" ]; then
    SELECTED_BUNDLES="$PRESELECT_BUNDLES"
    ok "Pre-selected bundles: $SELECTED_BUNDLES"
    _log "PRE-SELECTED BUNDLES: $SELECTED_BUNDLES"
else
    echo -e "  ${C_FG}Choose which language toolchains to install:${C_RESET}"
    echo ""
    echo -e "  ${C_TYPE}Python${C_RESET} — uv, ruff, pyrefly (LSP), ty"
    echo -e "  ${C_TYPE}Go${C_RESET}     — Go 1.21+ (apt + tarball upgrade)"
    echo -e "  ${C_TYPE}Rust${C_RESET}   — Rust stable via rustup (minimal profile)"
    echo ""

    SELECTED_BUNDLES=$(_multiselect "Select bundles" python go rust)
fi

if [ -n "$SELECTED_BUNDLES" ]; then
    info "Installing: $SELECTED_BUNDLES"
    echo ""

    # Install apt prerequisites for selected bundles first
    OPEN_CHAD_BUNDLES="$SELECTED_BUNDLES" \
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
        bash "$REPO_DIR/lib/setup_ubuntu_deps.sh" || true

    # Install the actual language toolchains
    OPEN_CHAD_BUNDLES="$SELECTED_BUNDLES" \
    OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
    OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
        bash "$REPO_DIR/lib/setup_dev_bundle.sh" || {
        warn "Some bundles had errors. Check: $OPEN_CHAD_INSTALL_LOG"
    }
    ok "Bundle installation complete"
    _log "BUNDLES INSTALLED: $SELECTED_BUNDLES"
else
    info "No bundles selected — skipping language toolchain install"
    _log "NO BUNDLES SELECTED"
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4: MCP Servers
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 4 "$TOTAL_STEPS" "MCP Server Configuration"

if [ "$SKIP_MCP" -eq 1 ]; then
    skip "MCP servers (--skip-mcp)"
else
    info "Wiring context7, grep-app, lgrep (enabled)"
    info "Registering firecrawl, brave-web-search (disabled)"
    echo ""
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
    OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
        bash "$REPO_DIR/lib/setup_mcp.sh" || {
        warn "MCP setup had errors. Check: $OPEN_CHAD_INSTALL_LOG"
    }
    ok "MCP servers configured"
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5: Plugins (ADV + morph)
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 5 "$TOTAL_STEPS" "OpenCode Plugins"

if [ "$SKIP_ADV" -eq 1 ]; then
    skip "ADV plugin (--skip-adv)"
else
    info "Installing ADV (Advance) plugin..."
    if OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
        bash "$REPO_DIR/lib/setup_adv.sh"; then
        ok "ADV plugin configured"
    else
        warn "ADV setup had errors (non-fatal). Install pnpm and retry: bash lib/setup_adv.sh"
    fi
fi

if [ "$SKIP_MORPH" -eq 1 ]; then
    skip "morph-fast-apply (--skip-morph)"
else
    info "Installing morph-fast-apply plugin..."
    if OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
        bash "$REPO_DIR/lib/setup_morph.sh"; then
        ok "morph-fast-apply configured"
    else
        warn "morph setup had errors (non-fatal). Retry: bash lib/setup_morph.sh"
    fi
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: OpenCode Config (agents, instructions, theme)
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 6 "$TOTAL_STEPS" "OpenCode Config & Agents"

info "Syncing agents, instructions, and theme..."
OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
    bash "$REPO_DIR/lib/setup_opencode.sh" || {
    warn "OpenCode config setup had errors. Check: $OPEN_CHAD_INSTALL_LOG"
}
ok "Agents, instructions, and theme synced"
_log "OPENCODE CONFIG DONE"
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7: Windows Terminal Keybindings
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 7 "$TOTAL_STEPS" "Windows Terminal Keybindings (optional)"

if [ "$YES_MODE" -eq 0 ]; then
    echo -e "  ${C_FG}If you're using Windows Terminal + WSL, these keybindings enable${C_RESET}"
    echo -e "  ${C_FG}Shift+Enter and Ctrl+Backspace for better OpenCode experience.${C_RESET}"
    echo ""
    echo -e "  ${C_ACCENT}Add to Windows Terminal settings.json → actions array:${C_RESET}"
    echo ""
    echo -e '  {
    "command": {
      "action": "sendInput",
      "input": "\u001b[13;2u"
    },
    "keys": "shift+enter"
  },
  {
    "command": {
      "action": "sendInput",
      "input": "\u001b[127;5u"
    },
    "keys": "ctrl+backspace"
  }'
    echo ""
    echo -e "  ${C_COMMENT}Settings.json location: %LOCALAPPDATA%\\Packages\\Microsoft.WindowsTerminal_*\\LocalState\\settings.json${C_RESET}"
    echo ""
    _log "WINDOWS TERMINAL STEP DISPLAYED"
    _confirm "Done reviewing Windows Terminal settings?" "y" || true
else
    _log "WINDOWS TERMINAL STEP SKIPPED (--yes mode)"
    info "Windows Terminal keybinding info skipped in --yes mode"
    info "See README.md for the keybinding JSON to add"
fi
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# Fallback: OpenCode prompt block
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$YES_MODE" -eq 0 ]; then
    echo ""
    echo -e "${C_COMMENT}──────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_ACCENT}Fallback: Paste into OpenCode to verify setup${C_RESET}"
    echo -e "${C_COMMENT}──────────────────────────────────────────────────────${C_RESET}"
    echo ""
    echo -e "  ${C_FG}Once you launch OpenCode, paste this prompt to verify everything works:${C_RESET}"
    echo ""
    echo -e "  ${C_COMMENT}┌─────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_COMMENT}│ Hello! Please confirm:                                       │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 1. You can see this message (auth works)                     │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 2. Run: /adv-status (ADV plugin works)                      │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 3. Run: lgrep_search q=\"hello world\"  (lgrep MCP works)     │${C_RESET}"
    echo -e "  ${C_COMMENT}└─────────────────────────────────────────────────────────────┘${C_RESET}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Done
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${C_STRING}╔══════════════════════════════════════════════════════╗${C_RESET}"
echo -e "${C_STRING}║           open-chad installation complete!           ║${C_RESET}"
echo -e "${C_STRING}╚══════════════════════════════════════════════════════╝${C_RESET}"
echo ""
echo -e "  ${C_FG}Launch OpenCode with:${C_RESET}  ${C_TYPE}open-chad${C_RESET}"
echo -e "  ${C_FG}Update open-chad:${C_RESET}       ${C_TYPE}open-chad update${C_RESET}"
echo -e "  ${C_FG}Discord presence:${C_RESET}       ${C_TYPE}open-chad discord enable${C_RESET}"
echo ""
echo -e "  ${C_COMMENT}Install log: $OPEN_CHAD_INSTALL_LOG${C_RESET}"
echo ""

_log "=== wizard complete $(date -Iseconds) ==="
_log "SELECTED_BUNDLES=${SELECTED_BUNDLES:-none}"
_log_flush
