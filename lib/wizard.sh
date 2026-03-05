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
#   --skip-omp       Skip omp (model preferences) install
#   --skip-vision    Skip Vision MCP daemon setup
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
SKIP_OMP=0
SKIP_ZSH=0
SKIP_VISION=0
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
        --skip-omp)          SKIP_OMP=1;                   shift ;;
        --skip-zsh)          SKIP_ZSH=1;                   shift ;;
        --skip-vision)       SKIP_VISION=1;                shift ;;
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
            echo "  --skip-omp          Skip omp (model preferences) install"
            echo "  --skip-vision       Skip Vision MCP daemon setup"
            echo "  --skip-zsh          Skip zsh + plugin setup"
            echo "  --bundles <list>    Pre-select bundles (e.g. 'python go')"
            exit 0
            ;;
        *) shift ;;
    esac
done

# ─── Logging ──────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$OPEN_CHAD_INSTALL_LOG")"
if [ ! -f "$OPEN_CHAD_INSTALL_LOG" ]; then
    install -m 0600 /dev/null "$OPEN_CHAD_INSTALL_LOG"
else
    chmod 0600 "$OPEN_CHAD_INSTALL_LOG"
fi

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

    # All display output goes to stderr so command-substitution capture only gets the result
    echo -e "  ${C_ACCENT}Select bundles to install:${C_RESET} (Enter = all, 0 = none)" >&2
    echo -e "  ${C_COMMENT}Type numbers separated by spaces, e.g. '1 2' for Python and Go:${C_RESET}" >&2
    echo "" >&2
    for i in "${!options[@]}"; do
        echo -e "    ${C_TYPE}[$((i+1))]${C_RESET} ${options[$i]}" >&2
    done
    echo -e "    ${C_COMMENT}[0]${C_RESET} None (skip all bundles)" >&2
    echo "" >&2
    echo -ne "  ${C_ACCENT}?${C_RESET} Your selection [default: all]: " >&2
    local answer
    read -r answer
    _log "BUNDLE SELECTION INPUT: $answer"

    if [[ "$answer" == "0" ]]; then
        _log "BUNDLES SELECTED: (none)"
        echo ""
        return 0
    fi

    # Empty input = select all (default)
    if [[ -z "$answer" ]]; then
        _log "BUNDLES SELECTED: all (default)"
        echo "${options[*]}"
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
echo -e "${C_STRING}  ║${C_RESET}     ${C_ACCENT}open-chad v1.3 — Installation Wizard${C_RESET}     ${C_STRING}║${C_RESET}"
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

# ─── Component selection ──────────────────────────────────────────────────────
# Maps component index → SKIP variable name and display info.
# Core components (PATH, tmux theme, agents/instructions) are always installed.
# CLI --skip-* flags override selections (already-skipped components are locked).

_COMP_NAMES=(
    "System dependencies"
    "Claude OAuth"
    "Dev language bundles"
    "MCP servers"
    "Vision MCP daemon"
    "ADV plugin"
    "morph-fast-apply"
    "Model preferences (omp)"
    "Zsh + plugins"
)
_COMP_DESCS=(
    "git, curl, tmux, node, pnpm via apt"
    "Authenticate with Claude API"
    "Python, Go, Rust, Web toolchains"
    "context7, grep-app, lgrep, firecrawl"
    "Manages MCP server lifecycle"
    "Spec-driven development workflow"
    "Fast-apply edits for large files"
    "TUI for per-agent model selection"
    "powerlevel10k, autosuggestions, syntax highlighting"
)
# Parallel array: variable name that controls each component's skip state
_COMP_VARS=(
    SKIP_DEPS
    SKIP_AUTH
    SKIP_BUNDLES
    SKIP_MCP
    SKIP_VISION
    SKIP_ADV
    SKIP_MORPH
    SKIP_OMP
    SKIP_ZSH
)

_component_select() {
    # In --yes mode, install everything not already skipped via CLI flags
    if [ "$YES_MODE" -eq 1 ]; then
        _log "COMPONENT SELECT: --yes mode, using CLI flag defaults"
        return 0
    fi

    echo -e "${C_STRING}  ╔═══════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_STRING}  ║${C_RESET}  ${C_ACCENT}Choose components to install${C_RESET}                    ${C_STRING}║${C_RESET}"
    echo -e "${C_STRING}  ╚═══════════════════════════════════════════════╝${C_RESET}"
    echo ""
    echo -e "  ${C_FG}Core (always installed):${C_RESET}"
    echo -e "    ${C_COMMENT}·${C_RESET} Shell profile PATH setup"
    echo -e "    ${C_COMMENT}·${C_RESET} Tmux theme (ayu-dark)"
    echo -e "    ${C_COMMENT}·${C_RESET} OpenCode config (agents, instructions, theme)"
    echo ""
    echo -e "  ${C_FG}Optional components:${C_RESET}"
    echo ""

    local i
    for i in "${!_COMP_NAMES[@]}"; do
        local num=$((i + 1))
        local var="${_COMP_VARS[$i]}"
        local skip_val="${!var}"
        if [ "$skip_val" -eq 1 ]; then
            # Locked out by CLI flag — show as disabled
            printf "    ${C_COMMENT}[%d] %-28s %s (skipped via --skip flag)${C_RESET}\n" \
                "$num" "${_COMP_NAMES[$i]}" "—"
        else
            printf "    ${C_TYPE}[%d]${C_RESET} %-28s ${C_COMMENT}%s${C_RESET}\n" \
                "$num" "${_COMP_NAMES[$i]}" "${_COMP_DESCS[$i]}"
        fi
    done

    echo ""
    echo -e "  ${C_COMMENT}Enter = install all  ·  0 = none  ·  Type numbers to select (e.g. 1 3 5 6)${C_RESET}"
    echo ""
    echo -ne "  ${C_ACCENT}?${C_RESET} Components to install [default: all]: "

    local answer
    read -r answer
    _log "COMPONENT SELECTION INPUT: $answer"

    # Empty = all (default)
    if [ -z "$answer" ]; then
        _log "COMPONENT SELECT: all (default)"
        return 0
    fi

    # 0 = none
    if [ "$answer" = "0" ]; then
        _log "COMPONENT SELECT: none"
        for i in "${!_COMP_VARS[@]}"; do
            local var="${_COMP_VARS[$i]}"
            # Only set if not already locked by CLI flag
            if [ "${!var}" -eq 0 ]; then
                eval "$var=1"
            fi
        done
        return 0
    fi

    # Specific numbers: skip everything not selected (unless locked by CLI)
    # First, mark all unlocked components as skipped
    for i in "${!_COMP_VARS[@]}"; do
        local var="${_COMP_VARS[$i]}"
        if [ "${!var}" -eq 0 ]; then
            eval "$var=1"
        fi
    done

    # Then un-skip the selected ones
    for num in $answer; do
        local idx=$((num - 1))
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#_COMP_VARS[@]}" ]; then
            local var="${_COMP_VARS[$idx]}"
            eval "$var=0"
            _log "COMPONENT SELECTED: ${_COMP_NAMES[$idx]}"
        fi
    done

    # Show summary
    echo ""
    echo -e "  ${C_FG}Selected:${C_RESET}"
    local any_selected=0
    for i in "${!_COMP_NAMES[@]}"; do
        local var="${_COMP_VARS[$i]}"
        if [ "${!var}" -eq 0 ]; then
            echo -e "    ${C_STRING}✓${C_RESET} ${_COMP_NAMES[$i]}"
            any_selected=1
        fi
    done
    if [ "$any_selected" -eq 0 ]; then
        echo -e "    ${C_COMMENT}(none)${C_RESET}"
    fi
    echo ""
}

_component_select

# Count active steps for progress display
_count_active_steps() {
    local count=3  # Core steps always run: shell profile, tmux theme, opencode config
    [ "$SKIP_DEPS" -eq 0 ]     && count=$((count + 1))
    [ "$SKIP_AUTH" -eq 0 ]     && count=$((count + 1))
    [ "$SKIP_BUNDLES" -eq 0 ]  && count=$((count + 1))
    [ "$SKIP_MCP" -eq 0 ]      && count=$((count + 1))
    [ "$SKIP_VISION" -eq 0 ]   && count=$((count + 1))
    [ "$SKIP_ADV" -eq 0 ]      && count=$((count + 1))
    [ "$SKIP_MORPH" -eq 0 ]    && count=$((count + 1))
    [ "$SKIP_OMP" -eq 0 ]      && count=$((count + 1))
    [ "$SKIP_ZSH" -eq 0 ]      && count=$((count + 1))
    echo "$count"
}

TOTAL_STEPS=10

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

# Wire shell profile (idempotent — safe to call even if already done)
info "Wiring ~/.local/bin into shell profile..."
bash "$REPO_DIR/lib/setup_shell_profile.sh" || true
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

# Normalize bundle input: accept comma-separated or space-separated, strip extras
_normalize_bundles() {
    local raw="$1"
    # Replace commas with spaces, collapse whitespace, filter to known tokens
    local normalized
    normalized=$(echo "$raw" | tr ',' ' ' | tr -s ' ' | xargs)
    local result=()
    for token in $normalized; do
        case "$token" in
            python|go|rust|web) result+=("$token") ;;
            *) _log "WARN: unknown bundle token ignored: $token" ;;
        esac
    done
    echo "${result[*]:-}"
}

if [ "$SKIP_BUNDLES" -eq 1 ]; then
    skip "dev bundles (--skip-bundles)"
elif [ -n "$PRESELECT_BUNDLES" ]; then
    SELECTED_BUNDLES=$(_normalize_bundles "$PRESELECT_BUNDLES")
    ok "Pre-selected bundles: $SELECTED_BUNDLES"
    _log "PRE-SELECTED BUNDLES: $SELECTED_BUNDLES"
else
    echo -e "  ${C_FG}Choose which language toolchains to install:${C_RESET}"
    echo ""
    echo -e "  ${C_TYPE}Python${C_RESET} — uv, ruff, pyrefly (LSP), ty"
    echo -e "  ${C_TYPE}Go${C_RESET}     — Go 1.21+ (apt + tarball upgrade)"
    echo -e "  ${C_TYPE}Rust${C_RESET}   — Rust stable via rustup (minimal profile)"
    echo -e "  ${C_TYPE}Web${C_RESET}    — TypeScript, typescript-language-server (for Svelte/Vite)"
    echo ""

    SELECTED_BUNDLES=$(_multiselect "Select bundles" python go rust web)
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
    info "Wiring context7, grep-app, lgrep, firecrawl (enabled)"
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
# STEP 5: Vision Daemon Setup
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 5 "$TOTAL_STEPS" "Vision MCP Daemon"

if [ "$SKIP_VISION" -eq 1 ]; then
    skip "Vision daemon (--skip-vision)"
else
    info "Verifying Vision daemon and registering MCP servers..."
    info "Vision manages context7, grep-app, lgrep, firecrawl endpoints."
    echo ""
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
        bash "$REPO_DIR/lib/setup_vision.sh" || {
        warn "Vision setup had errors (non-fatal). MCP servers may be unavailable."
        warn "Ensure 'vision' binary is on PATH and retry: bash lib/setup_vision.sh"
    }
fi
_log "VISION SETUP DONE"
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6: Plugins (ADV + morph)
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 6 "$TOTAL_STEPS" "OpenCode Plugins"

if [ "$SKIP_ADV" -eq 1 ]; then
    skip "ADV plugin (--skip-adv)"
else
    _adv_mode="${ADV_INSTALL_MODE:-latest}"
    case "$_adv_mode" in
        latest)
            info "Installing ADV (Advance) plugin... [latest]"
            ;;
        offline)
            info "Installing ADV (Advance) plugin... [offline fallback]"
            ;;
        *)
            info "Installing ADV (Advance) plugin... [mode: $_adv_mode]"
            ;;
    esac
    if ADV_INSTALL_MODE="$_adv_mode" \
        OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
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
# STEP 7: OpenCode Config (agents, instructions, theme)
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 7 "$TOTAL_STEPS" "OpenCode Config & Agents"

info "Syncing agents, instructions, and theme..."
OPENCODE_CONFIG_DIR="$OPENCODE_CONFIG_DIR" \
    bash "$REPO_DIR/lib/setup_opencode.sh" || {
    warn "OpenCode config setup had errors. Check: $OPEN_CHAD_INSTALL_LOG"
}
ok "Agents, instructions, and theme synced"
_log "OPENCODE CONFIG DONE"
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8: OMP (opencode-model-preferences)
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 8 "$TOTAL_STEPS" "Model Preferences (omp)"

if [ "$SKIP_OMP" -eq 1 ]; then
    skip "omp (--skip-omp)"
else
    info "Installing omp (opencode-model-preferences)..."
    info "Requires Go 1.16+. Skipped gracefully if Go is not installed."
    echo ""
    if OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
        bash "$REPO_DIR/lib/setup_omp.sh"; then
        ok "omp installed"
    else
        warn "omp install had errors (non-fatal). Install Go 1.16+ and retry: bash lib/setup_omp.sh"
    fi
fi
_log "OMP STEP DONE"
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9: Zsh Shell Setup
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 9 "$TOTAL_STEPS" "Zsh Shell Setup"

if [ "$SKIP_ZSH" -eq 1 ]; then
    skip "zsh + plugin setup (--skip-zsh)"
else
    info "Installing zsh and plugins (powerlevel10k, zsh-autosuggestions, fast-syntax-highlighting)..."
    info "Plugins cloned to ~/.zsh/plugins/ — managed block added to ~/.zshrc"
    echo ""
    YES_MODE="$YES_MODE" \
    OPEN_CHAD_INSTALL_LOG="$OPEN_CHAD_INSTALL_LOG" \
        bash "$REPO_DIR/lib/setup_zsh_plugins.sh" || {
        warn "Zsh setup had errors. Check: $OPEN_CHAD_INSTALL_LOG"
    }
    ok "Zsh plugins configured"
fi
_log "ZSH SETUP DONE"
_log_flush

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 10: Windows Terminal Keybindings
# ═══════════════════════════════════════════════════════════════════════════════
_step_banner 10 "$TOTAL_STEPS" "Windows Terminal Keybindings (optional)"

# Detect WSL: check /proc/version for Microsoft kernel signature
_is_wsl=0
if [ -f /proc/version ] && grep -qi "microsoft" /proc/version 2>/dev/null; then
    _is_wsl=1
fi

if [ "$YES_MODE" -eq 0 ]; then
    echo -e "  ${C_FG}If you're using Windows Terminal + WSL, these keybindings enable${C_RESET}"
    echo -e "  ${C_FG}Shift+Enter and Ctrl+Backspace for better OpenCode experience.${C_RESET}"
    echo ""

    if [ "$_is_wsl" -eq 1 ]; then
        # On WSL: generate a PowerShell script the user can run directly
        _ps1_file="${HOME}/open-chad-keybindings.ps1"
        cat > "$_ps1_file" <<'PSEOF'
# open-chad-keybindings.ps1
# Generated by open-chad installer — run this in PowerShell (as your Windows user)
# to add Shift+Enter and Ctrl+Backspace keybindings to Windows Terminal.
#
# Usage: Open PowerShell on Windows, then run:
#   .\open-chad-keybindings.ps1

$settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (-not (Test-Path $settingsPath)) {
    # Fallback: Windows Terminal Preview or unpackaged install
    $settingsPath = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
}

if (-not (Test-Path $settingsPath)) {
    Write-Error "Windows Terminal settings.json not found. Is Windows Terminal installed?"
    exit 1
}

$settings = Get-Content $settingsPath -Raw | ConvertFrom-Json

$newBindings = @(
    @{
        command = @{ action = "sendInput"; input = "`e[13;2u" }
        keys    = "shift+enter"
    },
    @{
        command = @{ action = "sendInput"; input = "`e[127;5u" }
        keys    = "ctrl+backspace"
    }
)

if (-not $settings.actions) {
    $settings | Add-Member -NotePropertyName actions -NotePropertyValue @()
}

$existingKeys = $settings.actions | ForEach-Object { $_.keys }
foreach ($binding in $newBindings) {
    if ($existingKeys -notcontains $binding.keys) {
        $settings.actions += $binding
        Write-Host "Added keybinding: $($binding.keys)"
    } else {
        Write-Host "Keybinding already present: $($binding.keys)"
    }
}

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
Write-Host "Done. Restart Windows Terminal to apply changes."
PSEOF
        ok "WSL detected — generated PowerShell keybinding script:"
        info "  ${_ps1_file}"
        echo ""
        echo -e "  ${C_FG}Copy this file to Windows and run it in PowerShell:${C_RESET}"
        echo -e "  ${C_ACCENT}  cp ~/open-chad-keybindings.ps1 /mnt/c/Users/\$USER/${C_RESET}"
        echo -e "  ${C_ACCENT}  # Then in PowerShell: .\\open-chad-keybindings.ps1${C_RESET}"
        _log "WSL DETECTED: generated $HOME/open-chad-keybindings.ps1"
    else
        # Non-WSL: show manual instructions as before
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
        _log "WINDOWS TERMINAL STEP DISPLAYED (non-WSL)"
    fi
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
# Post-install verification prompt
# ═══════════════════════════════════════════════════════════════════════════════
_VERIFICATION_DOC="${OPENCODE_CONFIG_DIR}/instructions/post_install_verification.md"

if [ "$YES_MODE" -eq 0 ]; then
    echo ""
    echo -e "${C_COMMENT}──────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_ACCENT}Verify your setup in OpenCode${C_RESET}"
    echo -e "${C_COMMENT}──────────────────────────────────────────────────────${C_RESET}"
    echo ""
    echo -e "  ${C_FG}Once you launch OpenCode, paste this prompt to verify everything works:${C_RESET}"
    echo ""
    echo -e "  ${C_COMMENT}┌─────────────────────────────────────────────────────────────────┐${C_RESET}"
    echo -e "  ${C_COMMENT}│ Hello! I just installed open-chad. Please run through this       │${C_RESET}"
    echo -e "  ${C_COMMENT}│ checklist and confirm each item works:                           │${C_RESET}"
    echo -e "  ${C_COMMENT}│                                                                  │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 1. AUTH — You can read this message (Claude API auth works)      │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 2. ADV  — Run: /adv-status                                      │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 3. MCP  — Run: lgrep_search_semantic(q=\"hello world\", path=\".\")          │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 4. MORPH — Confirm morph_edit tool is in your tool list         │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 5. THEME — Confirm ayu-dark theme is active                     │${C_RESET}"
    echo -e "  ${C_COMMENT}│ 6. AGENTS — Confirm scout, refine, librarian, explore available │${C_RESET}"
    echo -e "  ${C_COMMENT}└─────────────────────────────────────────────────────────────────┘${C_RESET}"
    echo ""
    echo -e "  ${C_COMMENT}Full verification guide: ${C_TYPE}$_VERIFICATION_DOC${C_RESET}"
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
echo -e "  ${C_FG}Launch OpenCode with:${C_RESET}  ${C_TYPE}openchad${C_RESET}"
echo -e "  ${C_FG}Update open-chad:${C_RESET}       ${C_TYPE}openchad update${C_RESET}"
echo -e "  ${C_FG}Discord presence:${C_RESET}       ${C_TYPE}openchad discord enable${C_RESET}"
echo ""
echo -e "  ${C_COMMENT}Install log: $OPEN_CHAD_INSTALL_LOG${C_RESET}"
echo ""

_log "=== wizard complete $(date -Iseconds) ==="
_log "SELECTED_BUNDLES=${SELECTED_BUNDLES:-none}"
_log_flush
