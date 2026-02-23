#!/usr/bin/env bash
# lib/setup_opencode.sh — Sync OpenCode agents, ADV commands, and instructions
#
# Actions:
#   1. Sync bundled agent markdown files -> ~/.config/opencode/agents/
#   2. Sync ADV command files from checkout -> ~/.config/opencode/command/
#   3. Sync bundled instruction files -> ~/.config/opencode/instructions/
#   4. Merge instruction paths into ~/.config/opencode/opencode.json
#
# Flags:
#   --skip-commands    Skip ADV command sync (use when ADV checkout unavailable)
#
# Environment overrides:
#   ADV_CHECKOUT_DIR     — path to ADV checkout (default: ~/dev/oc-plugins/advance)
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

step()  { echo -e "${C_GOLD}[opencode]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[opencode] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[opencode] WARN:${C_RESET} $*"; }

# ─── Flag parsing ─────────────────────────────────────────────────────────────
SKIP_COMMANDS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-commands) SKIP_COMMANDS=1; shift ;;
        *) shift ;;  # ignore unknown flags
    esac
done

# ─── Configuration ────────────────────────────────────────────────────────────
ADV_CHECKOUT_DIR="${ADV_CHECKOUT_DIR:-$HOME/dev/oc-plugins/advance}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"

BUNDLE_AGENTS_DIR="$REPO_DIR/config/opencode/agents"
BUNDLE_INSTRUCTIONS_DIR="$REPO_DIR/config/opencode/instructions"

DEST_AGENTS_DIR="$OPENCODE_CONFIG_DIR/agents"
DEST_COMMANDS_DIR="$OPENCODE_CONFIG_DIR/command"
DEST_INSTRUCTIONS_DIR="$OPENCODE_CONFIG_DIR/instructions"

# ─── 1. Sync agent files ───────────────────────────────────────────────────────
step "Syncing agent files -> $DEST_AGENTS_DIR"
mkdir -p "$DEST_AGENTS_DIR"
for src in "$BUNDLE_AGENTS_DIR"/*.md; do
    [ -f "$src" ] || continue
    dest="$DEST_AGENTS_DIR/$(basename "$src")"
    cp "$src" "$dest"
    ok "agent: $(basename "$src")"
done

# ─── 2. Sync ADV command files ─────────────────────────────────────────────────
if [ "$SKIP_COMMANDS" -eq 0 ]; then
    ADV_COMMANDS_DIR="$ADV_CHECKOUT_DIR/plugin/commands"
    if [ -d "$ADV_COMMANDS_DIR" ]; then
        step "Syncing ADV commands from $ADV_COMMANDS_DIR -> $DEST_COMMANDS_DIR"
        mkdir -p "$DEST_COMMANDS_DIR"
        for src in "$ADV_COMMANDS_DIR"/*.md; do
            [ -f "$src" ] || continue
            dest="$DEST_COMMANDS_DIR/$(basename "$src")"
            cp "$src" "$dest"
            ok "command: $(basename "$src")"
        done
    else
        warn "ADV commands directory not found: $ADV_COMMANDS_DIR"
        warn "Run setup_adv.sh first, or use --skip-commands flag."
    fi
else
    warn "Skipping ADV command sync (--skip-commands)"
fi

# ─── 3. Sync instruction files ────────────────────────────────────────────────
step "Syncing instruction files -> $DEST_INSTRUCTIONS_DIR"
mkdir -p "$DEST_INSTRUCTIONS_DIR"
for filename in shell_strategy.md mcp-tools.md worktree-guide.md lbp.md; do
    src="$BUNDLE_INSTRUCTIONS_DIR/$filename"
    dest="$DEST_INSTRUCTIONS_DIR/$filename"
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        ok "instruction: $filename"
    else
        warn "Bundled instruction file missing: $src"
    fi
done

# ─── 4. Merge instruction paths into opencode.json ────────────────────────────
step "Wiring instructions into $OPENCODE_JSON"

INSTRUCTIONS_JSON="[$(
    for filename in shell_strategy.md mcp-tools.md worktree-guide.md lbp.md; do
        dest="$DEST_INSTRUCTIONS_DIR/$filename"
        # Use ~ expansion-safe path
        dest_display="${dest/#$HOME/\~}"
        echo -n "\"$dest_display\","
    done | sed 's/,$//'
)]"

bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
    "{\"instructions\":$INSTRUCTIONS_JSON}"
ok "Instructions merged into $OPENCODE_JSON"

ok "OpenCode setup complete."
