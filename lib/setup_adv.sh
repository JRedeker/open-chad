#!/usr/bin/env bash
# lib/setup_adv.sh — Install/update ADV (Advance) from GitHub
#
# Actions:
#   1. Clone or pull ADV to ~/dev/oc-plugins/advance/ (always latest)
#   2. Run pnpm install + pnpm build in the plugin subdirectory
#   3. Merge the plugin path into ~/.config/opencode/opencode.json
#
# Environment overrides:
#   ADVANCE_REPO         — git URL (default: https://github.com/Sharper-Flow/Advance.git)
#   ADV_CHECKOUT_DIR     — local path (default: ~/dev/oc-plugins/advance)
#   ADV_PLUGIN_SUBDIR    — plugin subdirectory (default: plugin)
#   OPENCODE_CONFIG_DIR  — opencode config dir (default: ~/.config/opencode)
#   ADV_INSTALL_MODE     — latest | offline (default: latest)
#
# Called by install.sh. Safe to call standalone.
# Non-fatal: all network/build failures fall back to bundled command docs.

set -uo pipefail

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
ADV_INSTALL_MODE="${ADV_INSTALL_MODE:-latest}"
ADVANCE_REPO="${ADVANCE_REPO:-https://github.com/Sharper-Flow/Advance.git}"
ADV_CHECKOUT_DIR="${ADV_CHECKOUT_DIR:-$HOME/dev/oc-plugins/advance}"
ADV_PLUGIN_SUBDIR="${ADV_PLUGIN_SUBDIR:-plugin}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
ADV_PLUGIN_DIR="$ADV_CHECKOUT_DIR/$ADV_PLUGIN_SUBDIR"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"

# Bundled command docs (offline fallback source)
BUNDLED_CMD_DIR="$REPO_DIR/config/opencode/command"
DEST_CMD_DIR="$OPENCODE_CONFIG_DIR/command"

step "ADV install mode: $ADV_INSTALL_MODE"

# ─── Bundled fallback sync ────────────────────────────────────────────────────
# TWO-TIER FALLBACK ONLY: network clone/build -> bundled config/opencode/command/
# There is NO third tier. Do not add additional fallback layers here.
# If both tiers fail, exit 0 with a WARN (non-fatal installer behavior).
_sync_bundled_commands() {
    if [ -d "$BUNDLED_CMD_DIR" ]; then
        mkdir -p "$DEST_CMD_DIR"
        cp "$BUNDLED_CMD_DIR"/adv-*.md "$DEST_CMD_DIR/" 2>/dev/null || true
        ok "Bundled ADV command docs synced to $DEST_CMD_DIR"
    else
        warn "Bundled command dir not found: $BUNDLED_CMD_DIR"
    fi
}

# ─── Offline mode — skip all network, sync bundled only ──────────────────────
if [ "$ADV_INSTALL_MODE" = "offline" ]; then
    step "Offline mode — syncing bundled ADV command docs only"
    _sync_bundled_commands
    ok "ADV offline setup complete."
    exit 0
fi

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v pnpm &>/dev/null; then
    warn "pnpm not found in PATH. Falling back to bundled ADV command docs."
    warn "To install ADV fully, install pnpm and re-run:"
    warn "  npm install -g pnpm"
    warn "  bash $REPO_DIR/lib/setup_adv.sh"
    _sync_bundled_commands
    exit 0
fi

if ! command -v node &>/dev/null; then
    warn "node not found in PATH. Falling back to bundled ADV command docs."
    _sync_bundled_commands
    exit 0
fi

# ─── Git clone or pull (always latest) ────────────────────────────────────────
_do_git_setup() {
    if [ -d "$ADV_CHECKOUT_DIR/.git" ]; then
        step "Updating ADV checkout at $ADV_CHECKOUT_DIR"
        if ! git -C "$ADV_CHECKOUT_DIR" pull --no-edit --quiet 2>/dev/null; then
            warn "git pull failed — falling back to bundled ADV command docs."
            warn "Resolve manually: cd $ADV_CHECKOUT_DIR && git status"
            return 1
        fi
    elif [ -d "$ADV_CHECKOUT_DIR" ]; then
        # Directory exists but is not a git repo (partial/failed clone) — quarantine it
        local local_bak="$ADV_CHECKOUT_DIR.bak.$(date +%s)"
        warn "Directory exists but is not a git repo: $ADV_CHECKOUT_DIR"
        warn "Quarantining to: $local_bak"
        mv "$ADV_CHECKOUT_DIR" "$local_bak"
        step "Cloning ADV from $ADVANCE_REPO -> $ADV_CHECKOUT_DIR"
        mkdir -p "$(dirname "$ADV_CHECKOUT_DIR")"
        if ! git clone "$ADVANCE_REPO" "$ADV_CHECKOUT_DIR" 2>/dev/null; then
            warn "git clone failed — falling back to bundled ADV command docs."
            return 1
        fi
    else
        step "Cloning ADV from $ADVANCE_REPO -> $ADV_CHECKOUT_DIR"
        mkdir -p "$(dirname "$ADV_CHECKOUT_DIR")"
        if ! git clone "$ADVANCE_REPO" "$ADV_CHECKOUT_DIR" 2>/dev/null; then
            warn "git clone failed — falling back to bundled ADV command docs."
            return 1
        fi
    fi
    return 0
}

if ! _do_git_setup; then
    _sync_bundled_commands
    exit 0
fi

ok "ADV source at $ADV_CHECKOUT_DIR (latest)"

# ─── Build plugin ─────────────────────────────────────────────────────────────
if [ ! -d "$ADV_PLUGIN_DIR" ]; then
    warn "Expected plugin directory not found: $ADV_PLUGIN_DIR"
    warn "The ADV repository structure may have changed."
    warn "Falling back to bundled ADV command docs."
    _sync_bundled_commands
    exit 0
fi

step "Installing ADV plugin dependencies (pnpm install)"
if ! pnpm install --dir "$ADV_PLUGIN_DIR" --silent 2>/dev/null; then
    warn "pnpm install failed — falling back to bundled ADV command docs."
    _sync_bundled_commands
    exit 0
fi

step "Building ADV plugin (pnpm build)"
if ! pnpm --dir "$ADV_PLUGIN_DIR" run build 2>/dev/null; then
    warn "pnpm build failed — falling back to bundled ADV command docs."
    _sync_bundled_commands
    exit 0
fi

ok "ADV plugin built at $ADV_PLUGIN_DIR"

# ─── Wire plugin into opencode.json ───────────────────────────────────────────
step "Wiring ADV plugin into $OPENCODE_JSON"
if bash "$REPO_DIR/lib/json_merge.sh" --backup --rotate 5 "$OPENCODE_JSON" \
    "{\"plugin\":[\"$ADV_PLUGIN_DIR\"]}"; then
    ok "Plugin entry added/confirmed: $ADV_PLUGIN_DIR"
else
    warn "Failed to wire ADV plugin into $OPENCODE_JSON — json_merge.sh exited non-zero"
fi

# ─── Wire ADV instructions into opencode.json ─────────────────────────────────
ADV_INSTRUCTIONS_FILE="$ADV_CHECKOUT_DIR/ADV_INSTRUCTIONS.md"
if [ -f "$ADV_INSTRUCTIONS_FILE" ]; then
    step "Wiring ADV instructions into $OPENCODE_JSON"
    if bash "$REPO_DIR/lib/json_merge.sh" --backup --rotate 5 "$OPENCODE_JSON" \
        "{\"instructions\":[\"$ADV_INSTRUCTIONS_FILE\"]}"; then
        ok "Instructions entry added/confirmed: $ADV_INSTRUCTIONS_FILE"
    else
        warn "Failed to wire ADV instructions into $OPENCODE_JSON — json_merge.sh exited non-zero"
    fi
fi

# ─── Wire ADV worker agent stubs into opencode.json ──────────────────────────
# These are sub-agent role stubs used by ADV commands (adv-apply, adv-review,
# adv-harden, adv-slop-scan, etc.). They have no model assigned — users assign
# models via OMP. json_merge.sh is idempotent: existing entries are not clobbered,
# so user-assigned models are preserved across re-installs.
step "Wiring ADV worker agent stubs into $OPENCODE_JSON"
ADV_WORKER_STUBS='{
  "agent": {
    "adv-research-lead": {
      "mode": "subagent",
      "hidden": true,
      "description": "Lead research orchestrator — synthesizes librarian + adv-researcher findings"
    },
    "adv-prepper": {
      "mode": "subagent",
      "hidden": true,
      "description": "Gap analysis — adds missing scenarios, tasks, and dependencies before implementation"
    },
    "adv-reviewer": {
      "mode": "subagent",
      "hidden": true,
      "description": "Lead review synthesizer — 12-dimension code review, emits REVIEW_FINDINGS"
    },
    "adv-security-reviewer": {
      "mode": "subagent",
      "hidden": true,
      "description": "OWASP-focused security deep scan worker for /adv-review"
    },
    "adv-logic-reviewer": {
      "mode": "subagent",
      "hidden": true,
      "description": "Logic, edge cases, and concurrency review worker for /adv-review"
    },
    "adv-hardener": {
      "mode": "subagent",
      "hidden": true,
      "description": "Lead hardening synthesizer — gates archive on coverage, slop, and doc hygiene"
    },
    "adv-hardener-coverage": {
      "mode": "subagent",
      "hidden": true,
      "description": "Test coverage and production readiness harden worker"
    },
    "adv-hardener-docs": {
      "mode": "subagent",
      "hidden": true,
      "description": "Documentation hygiene harden worker — checks stale refs and inline docs"
    },
    "adv-hardener-slop": {
      "mode": "subagent",
      "hidden": true,
      "description": "AI slop and cleanup harden worker — detects copy-paste, temp artifacts"
    },
    "adv-slop-scanner": {
      "mode": "subagent",
      "hidden": true,
      "description": "Lead slop-scan orchestrator — synthesizes category worker reports"
    },
    "adv-slop-worker": {
      "mode": "subagent",
      "hidden": true,
      "description": "Slop-scan heuristic category worker — defensive code, nesting, complexity"
    }
  }
}'
if bash "$REPO_DIR/lib/json_merge.sh" --backup --rotate 5 "$OPENCODE_JSON" "$ADV_WORKER_STUBS"; then
    ok "ADV worker agent stubs wired into $OPENCODE_JSON"
else
    warn "Failed to wire ADV worker stubs into $OPENCODE_JSON — json_merge.sh exited non-zero"
fi

# ─── Sync bundled command docs (always — ensures offline fallback is current) ──
_sync_bundled_commands

ok "ADV setup complete."
