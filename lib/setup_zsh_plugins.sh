#!/usr/bin/env bash
# lib/setup_zsh_plugins.sh — Zsh + plugin setup for open-chad
#
# Actions:
#   1. Install zsh via apt if not present
#   2. Clone or update three plugins into ~/.zsh/plugins/:
#        - romkatv/powerlevel10k
#        - zsh-users/zsh-autosuggestions
#        - zdharma-continuum/fast-syntax-highlighting
#   3. Write (or update) a managed OPEN-CHAD ZSH BEGIN/END block in ~/.zshrc
#      that sources the plugins in the correct order. Idempotent — safe to re-run.
#
# Plugin order (fast-syntax-highlighting MUST be last):
#   powerlevel10k → zsh-autosuggestions → fast-syntax-highlighting
#
# Environment overrides:
#   ZSH_PLUGINS_DIR        — plugin install dir (default: ~/.zsh/plugins)
#   OPEN_CHAD_INSTALL_LOG  — log file (default: /tmp/open-chad-install.log)
#   YES_MODE               — set to 1 to skip interactive chsh prompt
#
# Called by wizard.sh (Step 8) and update.sh. Safe to call standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors (ayu-dark) ────────────────────────────────────────────────────────
C_GOLD=$'\e[38;2;230;180;80m'
C_STRING=$'\e[38;2;170;217;76m'
C_KEYWORD=$'\e[38;2;255;143;64m'
C_RESET=$'\e[0m'

step()  { echo -e "${C_GOLD}[zsh]${C_RESET} $*"; }
ok()    { echo -e "${C_STRING}[zsh] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_KEYWORD}[zsh] WARN:${C_RESET} $*"; }
error() { echo -e "${C_KEYWORD}[zsh] ERROR:${C_RESET} $*" >&2; }
log()   { echo "[$(date -Iseconds)] zsh: $*" >> "$INSTALL_LOG"; }

# ─── Configuration ────────────────────────────────────────────────────────────
ZSH_PLUGINS_DIR="${ZSH_PLUGINS_DIR:-$HOME/.zsh/plugins}"
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"
YES_MODE="${YES_MODE:-0}"
ZSHRC="$HOME/.zshrc"

if [ -z "$ZSH_PLUGINS_DIR" ]; then
    warn "ZSH_PLUGINS_DIR is empty; falling back to $HOME/.zsh/plugins"
    ZSH_PLUGINS_DIR="$HOME/.zsh/plugins"
fi

# Managed block markers
BLOCK_BEGIN="# >>> OPEN-CHAD ZSH BEGIN <<<"
BLOCK_END="# >>> OPEN-CHAD ZSH END <<<"

# Plugin definitions: "name|repo_url"
PLUGINS=(
    "powerlevel10k|https://github.com/romkatv/powerlevel10k.git"
    "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git"
    "fast-syntax-highlighting|https://github.com/zdharma-continuum/fast-syntax-highlighting.git"
)

log "Starting zsh plugin setup"

# ─── Step 1: Install zsh via apt ──────────────────────────────────────────────
if command -v zsh &>/dev/null; then
    ok "zsh already installed: $(command -v zsh)"
    log "zsh already present"
else
    step "Installing zsh via apt..."
    log "Installing zsh via apt"
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive sudo apt-get install -y zsh >> "$INSTALL_LOG" 2>&1 || {
            warn "apt-get install zsh failed — check $INSTALL_LOG"
            log "ERROR: apt-get install zsh failed"
            exit 1
        }
        ok "zsh installed"
        log "zsh installed via apt"
    else
        warn "apt-get not found — cannot install zsh automatically"
        warn "Please install zsh manually and re-run this script"
        log "WARN: apt-get not found, skipping zsh install"
        exit 1
    fi
fi

# ─── Step 2: Clone or update plugins ──────────────────────────────────────────
mkdir -p "$ZSH_PLUGINS_DIR"
log "Plugin directory: $ZSH_PLUGINS_DIR"

failed_plugins=()
available_plugins=0

_mark_plugin_failure() {
    local plugin_name="$1"
    failed_plugins+=("$plugin_name")
    log "Plugin failed: $plugin_name"
}

for plugin_def in "${PLUGINS[@]}"; do
    plugin_name="${plugin_def%%|*}"
    plugin_url="${plugin_def##*|}"
    plugin_dir="$ZSH_PLUGINS_DIR/$plugin_name"

    if [ -d "$plugin_dir/.git" ]; then
        step "Updating $plugin_name..."
        log "Updating plugin: $plugin_name"
        if git -C "$plugin_dir" pull --no-edit --quiet 2>> "$INSTALL_LOG"; then
            ok "$plugin_name updated"
            log "Plugin updated: $plugin_name"
            available_plugins=$((available_plugins + 1))
        else
            warn "$plugin_name update failed — using existing version"
            log "WARN: git pull failed for $plugin_name"
            available_plugins=$((available_plugins + 1))
        fi
    elif [ -d "$plugin_dir" ]; then
        # Directory exists but is not a git repo — quarantine and re-clone
        local_bak="${plugin_dir}.bak.$(date +%s)"
        warn "$plugin_dir exists but is not a git repo — quarantining to $local_bak"
        log "WARN: quarantining non-git dir: $plugin_dir -> $local_bak"
        mv "$plugin_dir" "$local_bak"
        step "Cloning $plugin_name from $plugin_url..."
        log "Cloning plugin: $plugin_name"
        if git clone --depth=1 "$plugin_url" "$plugin_dir" >> "$INSTALL_LOG" 2>&1; then
            ok "$plugin_name cloned"
            log "Plugin cloned: $plugin_name"
            available_plugins=$((available_plugins + 1))
            rm -rf "$local_bak"
        else
            error "Failed to clone $plugin_name"
            log "ERROR: git clone failed for $plugin_name"
            mv "$local_bak" "$plugin_dir" 2>/dev/null || true
            _mark_plugin_failure "$plugin_name"
            continue
        fi
    else
        step "Cloning $plugin_name from $plugin_url..."
        log "Cloning plugin: $plugin_name"
        if git clone --depth=1 "$plugin_url" "$plugin_dir" >> "$INSTALL_LOG" 2>&1; then
            ok "$plugin_name cloned"
            log "Plugin cloned: $plugin_name"
            available_plugins=$((available_plugins + 1))
        else
            error "Failed to clone $plugin_name"
            log "ERROR: git clone failed for $plugin_name"
            _mark_plugin_failure "$plugin_name"
            continue
        fi
    fi
done

if [ "${#failed_plugins[@]}" -gt 0 ]; then
    warn "Some plugins failed to install/update: ${failed_plugins[*]}"
fi

if [ "$available_plugins" -eq 0 ]; then
    error "No zsh plugins are available after setup. Aborting managed block update."
    exit 1
fi

# ─── Step 3: Write managed block in ~/.zshrc ──────────────────────────────────
# Ensure .zshrc exists
touch "$ZSHRC"

# Build the managed block content
# Plugin sourcing order: powerlevel10k → zsh-autosuggestions → fast-syntax-highlighting
# fast-syntax-highlighting MUST be last
_build_managed_block() {
    cat << BLOCK
$BLOCK_BEGIN
# Managed by open-chad — do not edit this block manually.
# To disable, remove this block or run: open-chad update --skip-zsh

# Zsh plugins
source "$ZSH_PLUGINS_DIR/powerlevel10k/powerlevel10k.zsh-theme" 2>/dev/null || true
source "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" 2>/dev/null || true
source "$ZSH_PLUGINS_DIR/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" 2>/dev/null || true
$BLOCK_END
BLOCK
}

_zshrc_lock_dir="${ZSHRC}.open-chad.lock"
if ! mkdir "$_zshrc_lock_dir" 2>/dev/null; then
    warn "Could not acquire .zshrc lock. Another setup may be running; skipping .zshrc update."
    log "WARN: lock acquisition failed for $ZSHRC"
else
    trap 'rmdir "$_zshrc_lock_dir" 2>/dev/null || true' EXIT

    has_begin=0
    has_end=0
    grep -qF "$BLOCK_BEGIN" "$ZSHRC" 2>/dev/null && has_begin=1 || true
    grep -qF "$BLOCK_END" "$ZSHRC" 2>/dev/null && has_end=1 || true

    if [ "$has_begin" -eq 1 ] && [ "$has_end" -eq 1 ]; then
        ok "Managed block already present in $ZSHRC — skipping (idempotent)"
        log "Managed block already present in .zshrc"
    else
        if [ "$has_begin" -eq 1 ] || [ "$has_end" -eq 1 ]; then
            warn "Detected incomplete managed block markers in $ZSHRC; appending a fresh complete block"
            log "WARN: incomplete managed block detected"
        fi
        step "Adding managed plugin block to $ZSHRC..."
        log "Appending managed block to .zshrc"
        {
            echo ""
            _build_managed_block
        } >> "$ZSHRC"
        ok "Managed block added to $ZSHRC"
        log "Managed block added to .zshrc"
    fi

    rmdir "$_zshrc_lock_dir" 2>/dev/null || true
    trap - EXIT
fi

# ─── Step 4: Optional chsh prompt (interactive mode only) ─────────────────────
if [ "${YES_MODE:-0}" = "0" ] && [ -t 0 ]; then
    current_shell="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "$SHELL")"
    zsh_path="$(command -v zsh)"
    if [ "$current_shell" != "$zsh_path" ]; then
        echo ""
        echo -e "  ${C_GOLD}?${C_RESET} Your current shell is ${current_shell}."
        echo -e "    Change default shell to zsh (${zsh_path})? [y/N] "
        answer=""
        read -r answer || answer="n"
        if [[ "$answer" =~ ^[Yy] ]]; then
            chsh -s "$zsh_path" && ok "Default shell changed to zsh" || \
                warn "chsh failed — change manually with: chsh -s $zsh_path"
            log "chsh to zsh: $answer"
        else
            log "chsh skipped by user"
        fi
    else
        log "Default shell is already zsh — skipping chsh"
    fi
else
    log "chsh prompt skipped (YES_MODE=$YES_MODE or non-interactive)"
fi

ok "Zsh plugin setup complete."
log "Zsh plugin setup complete"
