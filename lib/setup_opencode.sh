#!/usr/bin/env bash
# lib/setup_opencode.sh — Sync OpenCode agents, ADV commands, and instructions
#
# Actions:
#   1. Sync bundled agent markdown files -> ~/.config/opencode/agents/
#   2. Sync ADV command files from checkout -> ~/.config/opencode/command/
#   3. Sync bundled instruction files -> ~/.config/opencode/instructions/
#   4. Sync bundled theme files -> ~/.config/opencode/themes/
#   5. Sync bundled skill files -> ~/.config/opencode/skills/
#   6. Merge instruction paths + theme into ~/.config/opencode/opencode.json
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
PALETTE_FILE="$REPO_DIR/lib/agent_palette.sh"

if [ -f "$PALETTE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$PALETTE_FILE"
fi

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[opencode]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[opencode] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[opencode] WARN:${C_RESET} $*"; }

_is_valid_hex_color() {
    local value="${1:-}"
    [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]]
}

_default_color_for_agent() {
    if declare -F open_chad_agent_color >/dev/null 2>&1; then
        open_chad_agent_color "${1:-}"
        return 0
    fi

    case "${1:-}" in
        build) printf '%s' '#59C2FF' ;;
        plan) printf '%s' '#FFB454' ;;
        scout) printf '%s' '#F07178' ;;
        refine) printf '%s' '#AAD94C' ;;
        *) printf '%s' '' ;;
    esac
}

_read_agent_frontmatter_color() {
    local file="$1"
    [ -f "$file" ] || return 0

    awk '
        BEGIN { in_frontmatter=0; delimiter_count=0 }
        $0 == "---" && delimiter_count == 0 { in_frontmatter=1; delimiter_count=1; next }
        $0 == "---" && in_frontmatter == 1 { exit }
        in_frontmatter == 1 {
            if ($0 ~ /^color:[[:space:]]*/) {
                line=$0
                sub(/^color:[[:space:]]*/, "", line)
                gsub(/"/, "", line)
                print line
                exit
            }
        }
    ' "$file"
}

_resolve_agent_color() {
    local agent="$1"
    local fallback="$2"

    if ! command -v node &>/dev/null || [ ! -f "$OPEN_CHAD_CONFIG_FILE" ]; then
        printf '%s' "$fallback"
        return 0
    fi

    local configured
    configured=$(node - "$OPEN_CHAD_CONFIG_FILE" "$agent" "$fallback" <<'EOF'
const fs = require('fs');
const cfgPath = process.argv[2];
const agent = process.argv[3];
const fallback = process.argv[4];

try {
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const value = cfg && cfg.agentColors ? cfg.agentColors[agent] : undefined;
  if (typeof value === 'string') {
    process.stdout.write(value);
  } else {
    process.stdout.write(fallback);
  }
} catch (_) {
  process.stdout.write(fallback);
}
EOF
)

    if _is_valid_hex_color "$configured"; then
        printf '%s' "$configured"
    else
        printf '%s' "$fallback"
    fi
}

_seed_agent_colors_config() {
    if ! command -v node &>/dev/null; then
        warn "node not found; skipping persisted agent color migration"
        return 0
    fi

    local has_agent_colors=0
    if [ -f "$OPEN_CHAD_CONFIG_FILE" ]; then
        if node - "$OPEN_CHAD_CONFIG_FILE" <<'EOF' >/dev/null 2>&1
const fs = require('fs');
const cfgPath = process.argv[2];
try {
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  process.exit(cfg && cfg.agentColors && typeof cfg.agentColors === 'object' ? 0 : 1);
} catch (_) {
  process.exit(1);
}
EOF
        then
            has_agent_colors=0
        else
            has_agent_colors=1
        fi
    else
        has_agent_colors=1
    fi

    if [ "$has_agent_colors" -eq 0 ]; then
        return 0
    fi

    local build_color plan_color scout_color refine_color
    local detected

    build_color="$(_default_color_for_agent build)"
    detected="$(_read_agent_frontmatter_color "$DEST_AGENTS_DIR/build.md")"
    if _is_valid_hex_color "$detected"; then build_color="$detected"; fi

    plan_color="$(_default_color_for_agent plan)"
    detected="$(_read_agent_frontmatter_color "$DEST_AGENTS_DIR/plan.md")"
    if _is_valid_hex_color "$detected"; then plan_color="$detected"; fi

    scout_color="$(_default_color_for_agent scout)"
    detected="$(_read_agent_frontmatter_color "$DEST_AGENTS_DIR/scout.md")"
    if _is_valid_hex_color "$detected"; then scout_color="$detected"; fi

    refine_color="$(_default_color_for_agent refine)"
    detected="$(_read_agent_frontmatter_color "$DEST_AGENTS_DIR/refine.md")"
    if _is_valid_hex_color "$detected"; then refine_color="$detected"; fi

    local payload
    payload=$(printf '{"agentColors":{"build":"%s","plan":"%s","scout":"%s","refine":"%s"}}' \
        "$build_color" "$plan_color" "$scout_color" "$refine_color")

    if bash "$REPO_DIR/lib/json_merge.sh" "$OPEN_CHAD_CONFIG_FILE" "$payload" >/dev/null 2>&1; then
        ok "Persisted agent colors into $OPEN_CHAD_CONFIG_FILE"
    else
        warn "Failed to persist agent colors into $OPEN_CHAD_CONFIG_FILE"
    fi
}

_upsert_agent_frontmatter_color() {
    local file="$1"
    local color="$2"
    [ -f "$file" ] || return 0
    _is_valid_hex_color "$color" || return 0

    local tmp="${file}.$$"
    awk -v new_color="$color" '
        BEGIN { in_frontmatter=0; delimiter_count=0; color_set=0 }
        {
            if ($0 == "---" && delimiter_count == 0) {
                in_frontmatter=1
                delimiter_count=1
                print
                next
            }

            if ($0 == "---" && in_frontmatter == 1) {
                if (color_set == 0) {
                    print "color: \"" new_color "\""
                    color_set=1
                }
                in_frontmatter=0
                delimiter_count=2
                print
                next
            }

            if (in_frontmatter == 1 && $0 ~ /^color:[[:space:]]*/) {
                if (color_set == 0) {
                    print "color: \"" new_color "\""
                    color_set=1
                }
                next
            }

            print
        }
    ' "$file" > "$tmp"
    mv -f "$tmp" "$file"
}

_apply_primary_agent_colors() {
    local agent default_color resolved_color agent_file
    for agent in build plan scout refine; do
        default_color="$(_default_color_for_agent "$agent")"
        resolved_color="$(_resolve_agent_color "$agent" "$default_color")"
        agent_file="$DEST_AGENTS_DIR/${agent}.md"

        if [ ! -f "$agent_file" ]; then
            warn "agent color skipped; missing file: $(basename "$agent_file")"
            continue
        fi

        if ! _is_valid_hex_color "$resolved_color"; then
            warn "agent color invalid for '$agent' ('$resolved_color'); using default '$default_color'"
            resolved_color="$default_color"
        fi

        _upsert_agent_frontmatter_color "$agent_file" "$resolved_color"
        ok "agent color: ${agent} -> $resolved_color"
    done
}

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
OPEN_CHAD_CONFIG_FILE="${OPEN_CHAD_CONFIG_FILE:-$OPENCODE_CONFIG_DIR/open-chad.json}"

BUNDLE_AGENTS_DIR="$REPO_DIR/config/opencode/agents"
BUNDLE_INSTRUCTIONS_DIR="$REPO_DIR/config/opencode/instructions"
BUNDLE_THEMES_DIR="$REPO_DIR/config/opencode/themes"
BUNDLE_SKILLS_DIR="$REPO_DIR/config/opencode/skills"

DEST_AGENTS_DIR="$OPENCODE_CONFIG_DIR/agents"
DEST_COMMANDS_DIR="$OPENCODE_CONFIG_DIR/command"
DEST_INSTRUCTIONS_DIR="$OPENCODE_CONFIG_DIR/instructions"
DEST_THEMES_DIR="$OPENCODE_CONFIG_DIR/themes"
DEST_SKILLS_DIR="$OPENCODE_CONFIG_DIR/skills"

# Seed agent color persistence from existing local agent files before sync.
_seed_agent_colors_config

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

# Persisted primary agent accent colors always win over bundled defaults.
_apply_primary_agent_colors

# ─── 3. Sync instruction files ────────────────────────────────────────────────
step "Syncing instruction files -> $DEST_INSTRUCTIONS_DIR"
mkdir -p "$DEST_INSTRUCTIONS_DIR"
for filename in shell_strategy.md lbp.md temp_directory.md identity.md rules.yaml post_install_verification.md; do
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

# ─── 5. Sync skill files ──────────────────────────────────────────────────────
# Skills are on-demand instruction bundles loaded by the agent when relevant.
# Each skill lives in its own subdirectory: skills/<name>/SKILL.md
if [ -d "$BUNDLE_SKILLS_DIR" ]; then
    step "Syncing skill files -> $DEST_SKILLS_DIR"
    for skill_dir in "$BUNDLE_SKILLS_DIR"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_name="$(basename "$skill_dir")"
        dest_skill_dir="$DEST_SKILLS_DIR/$skill_name"
        mkdir -p "$dest_skill_dir"
        for src in "$skill_dir"*; do
            [ -f "$src" ] || continue
            _copy_if_regular "$src" "$dest_skill_dir/$(basename "$src")" "skill ($skill_name)"
        done
    done
else
    warn "Bundled skills directory missing: $BUNDLE_SKILLS_DIR"
fi

# ─── 6. Merge instruction paths + theme into opencode.json ────────────────────
step "Wiring instructions and theme into $OPENCODE_JSON"

INSTRUCTIONS_JSON="[$(
    for filename in shell_strategy.md lbp.md temp_directory.md identity.md rules.yaml post_install_verification.md; do
        dest="$DEST_INSTRUCTIONS_DIR/$filename"
        # Use ~ expansion-safe path
        dest_display="${dest/#$HOME/\~}"
        echo -n "\"$dest_display\","
    done | sed 's/,$//'
)]"

bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" \
    "{\"instructions\":$INSTRUCTIONS_JSON,\"theme\":\"ayu-dark\",\"plugin\":[\"@franlol/opencode-md-table-formatter@latest\"]}"
ok "Instructions, theme, and default plugins merged into $OPENCODE_JSON"

ok "OpenCode setup complete."
