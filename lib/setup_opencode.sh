#!/usr/bin/env bash
# lib/setup_opencode.sh — Sync OpenCode agents, ADV commands, and instructions
#
# Actions:
#   1. Sync bundled agent markdown files -> ~/.config/opencode/agents/
#   2. Sync ADV command files from checkout -> ~/.config/opencode/command/
#   3. Sync bundled instruction files -> ~/.config/opencode/instructions/
#   4. Sync bundled theme files -> ~/.config/opencode/themes/
#   5. Merge instruction paths + theme into ~/.config/opencode/opencode.json
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

_copy_if_regular() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [ -L "$src" ]; then
        warn "$label skipped symlink source: $(basename "$src")"
        return 0
    fi
    [ -f "$src" ] || return 0

    cp "$src" "$dest"
    ok "$label: $(basename "$src")"
}

# Copy an agent file, stripping any `model:` frontmatter line.
# Model preferences are user-managed via OMP — they must not be
# shipped in bundled or upstream-synced agent definitions.
_copy_agent() {
    local src="$1"
    local dest="$2"
    local label="$3"

    if [ -L "$src" ]; then
        warn "$label skipped symlink source: $(basename "$src")"
        return 0
    fi
    [ -f "$src" ] || return 0

    # Copy then strip model: line from YAML frontmatter (between --- markers)
    cp "$src" "$dest"
    if grep -q '^model:' "$dest" 2>/dev/null; then
        grep -v '^model:' "$dest" > "$dest.$$"
        mv -f "$dest.$$" "$dest"
        warn "$label: stripped 'model:' from $(basename "$src") (user-managed via OMP)"
    fi
    ok "$label: $(basename "$src")"
}

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
BUNDLE_THEMES_DIR="$REPO_DIR/config/opencode/themes"

DEST_AGENTS_DIR="$OPENCODE_CONFIG_DIR/agents"
DEST_COMMANDS_DIR="$OPENCODE_CONFIG_DIR/command"
DEST_INSTRUCTIONS_DIR="$OPENCODE_CONFIG_DIR/instructions"
DEST_THEMES_DIR="$OPENCODE_CONFIG_DIR/themes"

# ─── 1. Sync agent files ───────────────────────────────────────────────────────
step "Syncing agent files -> $DEST_AGENTS_DIR"
mkdir -p "$DEST_AGENTS_DIR"
for src in "$BUNDLE_AGENTS_DIR"/*.md; do
    dest="$DEST_AGENTS_DIR/$(basename "$src")"
    _copy_agent "$src" "$dest" "agent"
done

# ─── 2. Sync ADV command files ─────────────────────────────────────────────────
# ADV has used two layouts across versions:
#   legacy:  plugin/commands/
#   current: .opencode/command/
# Try current layout first, fall back to legacy.
if [ "$SKIP_COMMANDS" -eq 0 ]; then
    ADV_COMMANDS_DIR=""
    if [ -d "$ADV_CHECKOUT_DIR/.opencode/command" ]; then
        ADV_COMMANDS_DIR="$ADV_CHECKOUT_DIR/.opencode/command"
    elif [ -d "$ADV_CHECKOUT_DIR/plugin/commands" ]; then
        ADV_COMMANDS_DIR="$ADV_CHECKOUT_DIR/plugin/commands"
    fi

    if [ -n "$ADV_COMMANDS_DIR" ]; then
        step "Syncing ADV commands from $ADV_COMMANDS_DIR -> $DEST_COMMANDS_DIR"
        mkdir -p "$DEST_COMMANDS_DIR"
        for src in "$ADV_COMMANDS_DIR"/*.md; do
            dest="$DEST_COMMANDS_DIR/$(basename "$src")"
            _copy_if_regular "$src" "$dest" "command"
        done
    else
        # Two-tier fallback: network checkout -> bundled config/opencode/command/
        BUNDLED_CMD_DIR="$REPO_DIR/config/opencode/command"
        if [ -d "$BUNDLED_CMD_DIR" ] && ls "$BUNDLED_CMD_DIR"/adv-*.md &>/dev/null 2>&1; then
            warn "ADV checkout not found — using bundled command docs (offline fallback)"
            step "Syncing bundled ADV commands from $BUNDLED_CMD_DIR -> $DEST_COMMANDS_DIR"
            mkdir -p "$DEST_COMMANDS_DIR"
            for src in "$BUNDLED_CMD_DIR"/adv-*.md; do
                dest="$DEST_COMMANDS_DIR/$(basename "$src")"
                _copy_if_regular "$src" "$dest" "command (bundled)"
            done
        else
            warn "ADV commands directory not found in $ADV_CHECKOUT_DIR"
            warn "Checked: .opencode/command and plugin/commands"
            warn "Bundled fallback also unavailable: $BUNDLED_CMD_DIR"
            warn "Run setup_adv.sh first, or use --skip-commands flag."
        fi
    fi
else
    warn "Skipping ADV command sync (--skip-commands)"
fi

# ─── 2b. Sync ADV agent files (e.g. adv-researcher.md) ────────────────────────
# ADV ships its own sub-agent definitions in .opencode/agents/.
# When the checkout is present, prefer upstream versions over bundled fallbacks.
ADV_AGENTS_DIR="$ADV_CHECKOUT_DIR/.opencode/agents"
if [ -d "$ADV_AGENTS_DIR" ]; then
    step "Syncing ADV agents from $ADV_AGENTS_DIR -> $DEST_AGENTS_DIR"
    for src in "$ADV_AGENTS_DIR"/*.md; do
        dest="$DEST_AGENTS_DIR/$(basename "$src")"
        _copy_agent "$src" "$dest" "agent (adv)"
    done
fi

# ─── 3. Sync instruction files ────────────────────────────────────────────────
step "Syncing instruction files -> $DEST_INSTRUCTIONS_DIR"
mkdir -p "$DEST_INSTRUCTIONS_DIR"
for filename in shell_strategy.md mcp-tools.md worktree-guide.md lbp.md temp_directory.md identity.md rules.yaml post_install_verification.md; do
    src="$BUNDLE_INSTRUCTIONS_DIR/$filename"
    dest="$DEST_INSTRUCTIONS_DIR/$filename"
    if [ -f "$src" ]; then
        cp "$src" "$dest"
        ok "instruction: $filename"
    else
        warn "Bundled instruction file missing: $src"
    fi
done

# ─── 4. Sync theme files ──────────────────────────────────────────────────────
step "Syncing theme files -> $DEST_THEMES_DIR"
mkdir -p "$DEST_THEMES_DIR"
for src in "$BUNDLE_THEMES_DIR"/*.json; do
    dest="$DEST_THEMES_DIR/$(basename "$src")"
    _copy_if_regular "$src" "$dest" "theme"
done

# ─── 5. Merge instruction paths + theme into opencode.json ────────────────────
step "Wiring instructions and theme into $OPENCODE_JSON"

INSTRUCTIONS_JSON="[$(
    for filename in shell_strategy.md mcp-tools.md worktree-guide.md lbp.md temp_directory.md identity.md rules.yaml post_install_verification.md; do
        dest="$DEST_INSTRUCTIONS_DIR/$filename"
        # Use ~ expansion-safe path
        dest_display="${dest/#$HOME/\~}"
        echo -n "\"$dest_display\","
    done | sed 's/,$//'
)]"

bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
    "{\"instructions\":$INSTRUCTIONS_JSON,\"theme\":\"ayu-dark\"}"
ok "Instructions and theme merged into $OPENCODE_JSON"

ok "OpenCode setup complete."
