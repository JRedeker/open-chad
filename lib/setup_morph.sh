#!/usr/bin/env bash
# lib/setup_morph.sh — Install/update the morph-fast-apply OpenCode plugin
#
# Actions:
#   1. Clone or pull morph-fast-apply repo to ~/dev/oc-plugins/morph-fast-apply/
#   2. Run pnpm install + pnpm build in the plugin directory
#   3. Merge plugin path into ~/.config/opencode/opencode.json
#   4. Sync morph skill to ~/.config/opencode/skills/morph/
#
# Environment overrides:
#   MORPH_REPO           — git URL (default: https://github.com/anomalyco/morph-fast-apply.git)
#   MORPH_CHECKOUT_DIR   — local path (default: ~/dev/oc-plugins/morph-fast-apply)
#   OPENCODE_CONFIG_DIR  — opencode config dir (default: ~/.config/opencode)
#
# Called by install.sh and wizard.sh. Safe to call standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[morph]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[morph] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[morph] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[morph] ERROR:${C_RESET} $*" >&2; }

# ─── Configuration ────────────────────────────────────────────────────────────
MORPH_REPO="${MORPH_REPO:-https://github.com/anomalyco/morph-fast-apply.git}"
MORPH_CHECKOUT_DIR="${MORPH_CHECKOUT_DIR:-$HOME/dev/oc-plugins/morph-fast-apply}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"

# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
    warn "pnpm not found in PATH. Skipping morph install."
    warn "To install morph later, install pnpm and re-run:"
    warn "  npm install -g pnpm"
    warn "  bash $REPO_DIR/lib/setup_morph.sh"
    exit 0
fi

if ! command -v node &>/dev/null; then
    warn "node not found in PATH. Skipping morph install (required for json merge)."
    exit 0
fi

# ─── Git clone or pull ────────────────────────────────────────────────────────
if [ -d "$MORPH_CHECKOUT_DIR/.git" ]; then
    step "Updating morph-fast-apply at $MORPH_CHECKOUT_DIR"
    if ! git -C "$MORPH_CHECKOUT_DIR" pull --no-edit --quiet; then
        error "git pull failed — checkout may have local changes or be diverged."
        error "Resolve manually: cd $MORPH_CHECKOUT_DIR && git status"
        error "Aborting morph build to avoid using stale code."
        exit 1
    fi
elif [ -d "$MORPH_CHECKOUT_DIR" ]; then
    # Directory exists but is not a git repo (partial/failed clone) — quarantine it
    local_bak="$MORPH_CHECKOUT_DIR.bak.$(date +%s)"
    warn "Directory exists but is not a git repo: $MORPH_CHECKOUT_DIR"
    warn "Quarantining to: $local_bak"
    mv "$MORPH_CHECKOUT_DIR" "$local_bak"
    step "Cloning morph-fast-apply from $MORPH_REPO -> $MORPH_CHECKOUT_DIR"
    mkdir -p "$(dirname "$MORPH_CHECKOUT_DIR")"
    git clone "$MORPH_REPO" "$MORPH_CHECKOUT_DIR"
else
    step "Cloning morph-fast-apply from $MORPH_REPO -> $MORPH_CHECKOUT_DIR"
    mkdir -p "$(dirname "$MORPH_CHECKOUT_DIR")"
    git clone "$MORPH_REPO" "$MORPH_CHECKOUT_DIR"
fi
ok "morph source at $MORPH_CHECKOUT_DIR"

# ─── Build plugin ─────────────────────────────────────────────────────────────
# Determine plugin directory (may be root or a subdirectory named 'plugin')
if [ -f "$MORPH_CHECKOUT_DIR/plugin/package.json" ]; then
    MORPH_PLUGIN_DIR="$MORPH_CHECKOUT_DIR/plugin"
elif [ -f "$MORPH_CHECKOUT_DIR/package.json" ]; then
    MORPH_PLUGIN_DIR="$MORPH_CHECKOUT_DIR"
else
    error "No package.json found in morph checkout: $MORPH_CHECKOUT_DIR"
    error "The morph-fast-apply repo structure may have changed."
    exit 1
fi

step "Installing morph plugin dependencies (pnpm install)"
pnpm install --dir "$MORPH_PLUGIN_DIR" --silent

step "Building morph plugin (pnpm build)"
pnpm --dir "$MORPH_PLUGIN_DIR" run build

ok "morph plugin built at $MORPH_PLUGIN_DIR"

# ─── Wire plugin into opencode.json ──────────────────────────────────────────
mkdir -p "$OPENCODE_CONFIG_DIR"
[ -f "$OPENCODE_JSON" ] || echo '{}' > "$OPENCODE_JSON"

step "Wiring morph plugin into $OPENCODE_JSON"
bash "$REPO_DIR/lib/json_merge.sh" --backup --rotate 5 "$OPENCODE_JSON" \
    "{\"plugin\":[\"$MORPH_PLUGIN_DIR\"]}"
ok "Plugin entry added/confirmed: $MORPH_PLUGIN_DIR"

# ─── Sync morph skill ────────────────────────────────────────────────────────
# The morph skill provides on-demand guidance for using morph_edit.
# It lives in the morph checkout and is synced to the skills directory.
MORPH_SKILL_SRC_DIR="$MORPH_CHECKOUT_DIR/skills/morph"
DEST_SKILLS_DIR="$OPENCODE_CONFIG_DIR/skills"

if [ -d "$MORPH_SKILL_SRC_DIR" ]; then
    step "Syncing morph skill to $DEST_SKILLS_DIR/morph/"
    mkdir -p "$DEST_SKILLS_DIR/morph"
    for src in "$MORPH_SKILL_SRC_DIR"/*; do
        [ -f "$src" ] || continue
        cp "$src" "$DEST_SKILLS_DIR/morph/$(basename "$src")"
    done
    ok "Skill synced: morph/*"
else
    warn "morph skill directory not found at $MORPH_SKILL_SRC_DIR — skipping skill sync."
    warn "This is non-fatal; the plugin will still function."
fi

ok "morph-fast-apply setup complete."
