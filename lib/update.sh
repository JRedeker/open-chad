#!/usr/bin/env bash
# lib/update.sh — open-chad update backend
#
# Actions:
#   1. Validate this is a git-tracked install (.git directory check) [R5]
#   2. Validate working tree is clean (no uncommitted changes)
#   3. Detect diverged branch (commits ahead of origin) with recovery guide [R5]
#   4. git pull --ff-only
#   5. Re-run all setup modules (idempotent)
#   6. Re-apply language bundles from persisted install state [R4]
#
# Error handling: [A3NphMxA]
#   - Non-git install: clear error + releases URL
#   - Diverged branch: recovery guide (reset, stash, rebase)
#   - Dirty working tree: warning + option to continue
#   - Network failure: actionable steps
#   - All steps logged with timestamps
#
# Environment overrides:
#   OPEN_CHAD_CONFIG_FILE   — open-chad.json (default: ~/.config/opencode/open-chad.json)
#   OPEN_CHAD_INSTALL_LOG   — log file (default: /tmp/open-chad-install.log)
#   OPEN_CHAD_SKIP_BUNDLES  — if set, skip re-applying dev bundles
#
# Called by bin/open-chad update. Safe to call standalone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[update]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[update] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[update] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[update] ERROR:${C_RESET} $*" >&2; }
hint()  { echo -e "${C_CORAL}         ↳${C_RESET} $*" >&2; }
log()   {
    local msg="[$(date -Iseconds)] update: $*"
    echo "$msg" >> "$INSTALL_LOG"
    # Also print to stdout for visibility
}

# ─── Configuration ────────────────────────────────────────────────────────────
OPEN_CHAD_CONFIG_FILE="${OPEN_CHAD_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json}"
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"
SKIP_BUNDLES="${OPEN_CHAD_SKIP_BUNDLES:-0}"

RELEASES_URL="https://github.com/JRedeker/open-chad/releases"

# Initialize log
echo "=== open-chad update $(date -Iseconds) ===" >> "$INSTALL_LOG"

# ─── 1. Git installation check [R5] ──────────────────────────────────────────
step "Checking for git installation"
log "Checking .git directory at $REPO_DIR"

if [ ! -d "$REPO_DIR/.git" ]; then
    error "This open-chad install is not tracked by git."
    hint ""
    hint "The 'open-chad update' command requires a git clone."
    hint "Your install appears to have been extracted from a tarball or zip."
    hint ""
    hint "Options:"
    hint "  1. Download the latest release manually:"
    hint "     $RELEASES_URL"
    hint ""
    hint "  2. Re-install from git:"
    hint "     cd ~ && git clone https://github.com/JRedeker/open-chad.git"
    hint "     cd open-chad && bash install.sh"
    hint ""
    log "FAILED: no .git directory"
    exit 1
fi
ok "git repo confirmed at $REPO_DIR"
log "git repo confirmed"

# ─── 2. Check working tree is clean ──────────────────────────────────────────
step "Checking working tree status"
log "git status check"

_dirty=0
_status_output=$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)
if [ -n "$_status_output" ]; then
    warn "Working tree has uncommitted changes:"
    echo "$_status_output" | head -10 | while read -r line; do
        echo -e "    ${C_CORAL}$line${C_RESET}"
    done
    warn "git pull --ff-only may fail if local changes conflict."
    warn "Stash your changes before updating: git -C $REPO_DIR stash"
    _dirty=1
    log "WARNING: dirty working tree"
fi

# ─── 3. Diverged branch detection [R5] ───────────────────────────────────────
step "Checking branch sync with origin"
log "Fetching origin to check divergence"

# Fetch to get up-to-date remote refs (non-fatal if network down)
if ! git -C "$REPO_DIR" fetch --quiet origin 2>> "$INSTALL_LOG"; then
    warn "Could not reach origin (network issue?). Proceeding with local state."
    warn "If this fails, check your network connection."
    log "WARNING: fetch failed"
fi

_current_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "trunk")
_ahead=$(git -C "$REPO_DIR" rev-list "origin/$_current_branch..HEAD" 2>/dev/null | wc -l | tr -d ' ')

if [ "${_ahead:-0}" -gt 0 ]; then
    error "Local branch '$_current_branch' is $_ahead commit(s) AHEAD of origin."
    hint ""
    hint "git pull --ff-only will fail because your branch has diverged."
    hint ""
    hint "Recovery options:"
    hint ""
    hint "  Option A — Discard local commits (safest for open-chad):"
    hint "    git -C $REPO_DIR fetch origin"
    hint "    git -C $REPO_DIR reset --hard origin/$_current_branch"
    hint ""
    hint "  Option B — Stash local work and rebase:"
    hint "    git -C $REPO_DIR stash"
    hint "    git -C $REPO_DIR rebase origin/$_current_branch"
    hint ""
    hint "  Option C — Push your changes (if you're developing open-chad):"
    hint "    git -C $REPO_DIR push origin $_current_branch"
    hint ""
    hint "After resolving, re-run: open-chad update"
    log "FAILED: branch diverged ($_ahead commits ahead)"
    exit 1
fi
ok "Branch '$_current_branch' is in sync with origin"
log "Branch sync OK"

# ─── 4. git pull --ff-only ───────────────────────────────────────────────────
step "Pulling latest changes (git pull --ff-only)"
log "git pull --ff-only"

_pull_exit=0
git -C "$REPO_DIR" pull --ff-only --quiet 2>> "$INSTALL_LOG" || _pull_exit=$?

if [ "$_pull_exit" -ne 0 ]; then
    error "git pull --ff-only failed (exit $_pull_exit)."
    hint "This usually means local changes conflict with upstream."
    hint "Stash your changes: git -C $REPO_DIR stash"
    hint "Then re-run: open-chad update"
    hint "Check $INSTALL_LOG for git error details."
    log "FAILED: git pull exit $_pull_exit"
    exit 1
fi

_new_head=$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
ok "Pulled to $REPO_DIR ($current_branch @ $_new_head)"
log "git pull OK: HEAD=$_new_head"

# ─── 4b. Repair symlinks (open-chad + cds) ───────────────────────────────────
step "Ensuring ~/.local/bin symlinks are current"
_DEST_DIR="$HOME/.local/bin"
mkdir -p "$_DEST_DIR"

_repair_symlink() {
    local src="$1"
    local dest="$2"
    if [ -L "$dest" ] || [ -f "$dest" ]; then
        rm -f "$dest"
    fi
    ln -s "$src" "$dest"
    ok "Symlink: $(basename "$src") -> $dest"
}

_repair_symlink "$REPO_DIR/bin/open-chad" "$_DEST_DIR/open-chad"
_repair_symlink "$REPO_DIR/bin/cds"       "$_DEST_DIR/cds"
log "Symlinks repaired"

# ─── 5. Re-run setup modules ──────────────────────────────────────────────────
echo ""
step "Re-running setup modules..."
log "Starting setup module re-run"

# Environment check (non-fatal in update context — we're already installed)
if bash "$REPO_DIR/lib/check_environment.sh" 2>/dev/null; then
    ok "Environment checks passed"
else
    warn "Environment check had warnings (continuing update)"
fi

# MCP servers (idempotent — json_merge is additive, won't remove existing)
step "Updating MCP server configuration"
bash "$REPO_DIR/lib/setup_mcp.sh" || warn "MCP setup had errors (non-fatal)"
log "MCP setup done"

# Morph plugin (clone or pull + rebuild)
step "Updating morph-fast-apply plugin"
bash "$REPO_DIR/lib/setup_morph.sh" || warn "morph setup had errors (non-fatal)"
log "morph setup done"

# ADV plugin (clone or pull + rebuild)
step "Updating ADV plugin"
bash "$REPO_DIR/lib/setup_adv.sh" || warn "ADV setup had errors (non-fatal)"
log "ADV setup done"

# OpenCode agents, instructions, theme
step "Syncing OpenCode agents and instructions"
bash "$REPO_DIR/lib/setup_opencode.sh" || warn "OpenCode setup had errors (non-fatal)"
log "OpenCode setup done"

# ─── 6. Re-apply dev bundles from persisted state [R4] ────────────────────────
if [ "$SKIP_BUNDLES" != "1" ] && [ -f "$OPEN_CHAD_CONFIG_FILE" ]; then
    step "Reading persisted bundle selection from $OPEN_CHAD_CONFIG_FILE"
    log "Reading installer.selectedBundles from config"

    _bundles=$(node -e "
try {
    const fs=require('fs');
    const c=JSON.parse(fs.readFileSync('$OPEN_CHAD_CONFIG_FILE','utf8'));
    const b=(c.installer||{}).selectedBundles||[];
    process.stdout.write(b.join(' '));
} catch(e){ process.stdout.write(''); }
" 2>/dev/null || echo "")

    if [ -n "$_bundles" ]; then
        step "Re-applying bundles: $_bundles"
        log "Re-applying bundles: $_bundles"
        OPEN_CHAD_BUNDLES="$_bundles" \
        OPEN_CHAD_CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE" \
        OPEN_CHAD_INSTALL_LOG="$INSTALL_LOG" \
            bash "$REPO_DIR/lib/setup_dev_bundle.sh" || warn "Bundle re-apply had errors (non-fatal)"
        log "Bundle re-apply done"
    else
        ok "No bundles previously selected — skipping bundle re-apply"
        log "No bundles to re-apply"
    fi
else
    ok "Bundle re-apply skipped (OPEN_CHAD_SKIP_BUNDLES=1 or no config file)"
    log "Bundle re-apply skipped"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== open-chad update complete $(date -Iseconds) ===" >> "$INSTALL_LOG"
ok "open-chad update complete!"
ok "Log: $INSTALL_LOG"
echo ""
echo -e "  ${C_GOLD}Tip:${C_RESET} Restart open-chad sessions to pick up any theme/config changes."
  echo -e "  ${C_GOLD}Tip:${C_RESET} Re-wiring shell profile for PATH entries..."
  bash "$REPO_DIR/lib/setup_shell_profile.sh" || true
