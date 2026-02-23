#!/usr/bin/env bash
# lib/setup_adv.sh — Install/update ADV (Advance) from GitHub
#
# Actions:
#   1. Clone or pull the ADV repo to ~/dev/oc-plugins/advance/
#   2. Run pnpm install + pnpm build in the plugin subdirectory
#   3. Merge the plugin path into ~/.config/opencode/opencode.json
#
# Environment overrides:
#   ADVANCE_REPO         — git URL (default: https://github.com/Sharper-Flow/Advance.git)
#   ADV_CHECKOUT_DIR     — local path (default: ~/dev/oc-plugins/advance)
#   OPENCODE_CONFIG_DIR  — opencode config dir (default: ~/.config/opencode)
#
# Called by install.sh. Safe to call standalone.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[adv]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[adv] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[adv] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[adv] ERROR:${C_RESET} $*" >&2; }

# ─── Configuration ────────────────────────────────────────────────────────────
ADVANCE_REPO="${ADVANCE_REPO:-https://github.com/Sharper-Flow/Advance.git}"
ADV_CHECKOUT_DIR="${ADV_CHECKOUT_DIR:-$HOME/dev/oc-plugins/advance}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
ADV_PLUGIN_DIR="$ADV_CHECKOUT_DIR/plugin"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
    warn "pnpm not found in PATH. Skipping ADV install."
    warn "To install ADV later, install pnpm and re-run:"
    warn "  npm install -g pnpm"
    warn "  bash $REPO_DIR/lib/setup_adv.sh"
    exit 0
fi

if ! command -v node &>/dev/null; then
    warn "node not found in PATH. Skipping ADV install (required for json merge)."
    exit 0
fi

# ─── Git clone or pull ────────────────────────────────────────────────────────
if [ -d "$ADV_CHECKOUT_DIR/.git" ]; then
    step "Updating ADV checkout at $ADV_CHECKOUT_DIR"
    if ! git -C "$ADV_CHECKOUT_DIR" pull --no-edit --quiet; then
        error "git pull failed — checkout may have local changes or be diverged."
        error "Resolve manually: cd $ADV_CHECKOUT_DIR && git status"
        error "Aborting ADV build to avoid using stale code."
        exit 1
    fi
else
    step "Cloning ADV from $ADVANCE_REPO -> $ADV_CHECKOUT_DIR"
    mkdir -p "$(dirname "$ADV_CHECKOUT_DIR")"
    git clone "$ADVANCE_REPO" "$ADV_CHECKOUT_DIR"
fi
ok "ADV source at $ADV_CHECKOUT_DIR"

# ─── Build plugin ─────────────────────────────────────────────────────────────
if [ ! -d "$ADV_PLUGIN_DIR" ]; then
    error "Expected plugin directory not found: $ADV_PLUGIN_DIR"
    error "The ADV repository structure may have changed."
    exit 1
fi

step "Installing ADV plugin dependencies (pnpm install)"
pnpm install --dir "$ADV_PLUGIN_DIR" --silent

step "Building ADV plugin (pnpm build)"
pnpm --dir "$ADV_PLUGIN_DIR" run build

ok "ADV plugin built at $ADV_PLUGIN_DIR"

# ─── Wire plugin into opencode.json ───────────────────────────────────────────
step "Wiring ADV plugin into $OPENCODE_JSON"
bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
    "{\"plugin\":[\"$ADV_PLUGIN_DIR\"]}"
ok "Plugin entry added/confirmed: $ADV_PLUGIN_DIR"

# ─── Wire ADV instructions into opencode.json ─────────────────────────────────
ADV_INSTRUCTIONS_FILE="$ADV_CHECKOUT_DIR/ADV_INSTRUCTIONS.md"
if [ -f "$ADV_INSTRUCTIONS_FILE" ]; then
    step "Wiring ADV instructions into $OPENCODE_JSON"
    bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
        "{\"instructions\":[\"$ADV_INSTRUCTIONS_FILE\"]}"
    ok "Instructions entry added/confirmed: $ADV_INSTRUCTIONS_FILE"
fi

ok "ADV setup complete."
