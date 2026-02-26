#!/usr/bin/env bash
# lib/setup_vision.sh — Vision daemon setup for open-chad
#
# Verifies the Vision binary is on PATH and ensures the 4 open-chad MCP servers
# (context7, grep-app, lgrep, firecrawl) are registered in servers.yaml.
#
# Vision is a compiled binary daemon — NOT an npm package. It must be installed
# separately (system package or GitHub releases). This script does NOT install
# the binary; it validates presence and configures server registration.
#
# Server registration uses YAML at ~/.config/vision/servers.yaml.
# Existing entries are preserved (idempotent merge — never overwrites user config).
# servers.yaml is set to 0600 (owner-only) since it may contain API keys.
#
# If the daemon is already running, `vision daemon reload` is called to pick up
# any new server entries.
#
# Environment overrides:
#   OPEN_CHAD_INSTALL_LOG — log file path (default: /tmp/open-chad-install.log)
#   VISION_CONFIG_DIR     — vision config dir (default: ~/.config/vision)
#
# Exit codes:
#   0 — Setup complete (or binary missing with non-fatal warning)
#   1 — Fatal error (YAML write failed, config dir not writable)
#
# Called by wizard.sh, install.sh --yes, and update.sh. Safe to call standalone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[vision]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[vision] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[vision] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[vision] ERROR:${C_RESET} $*" >&2; }
hint()  { echo -e "${C_CORAL}       ↳${C_RESET} $*" >&2; }
audit() { echo "[$(date -Iseconds)] VISION: $*" >> "$INSTALL_LOG"; }

# ─── Configuration ────────────────────────────────────────────────────────────
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"
VISION_CONFIG_DIR="${VISION_CONFIG_DIR:-$HOME/.config/vision}"
VISION_YAML="$VISION_CONFIG_DIR/servers.yaml"

# ─── Step 1: Check Vision binary ─────────────────────────────────────────────
step "Checking Vision binary"

if ! command -v vision &>/dev/null; then
    warn "vision binary not found on PATH"
    hint "Vision is required for MCP server management (context7, grep-app, lgrep, firecrawl)."
    hint "Install Vision and ensure it is on PATH, then re-run: bash $SCRIPT_DIR/setup_vision.sh"
    hint "Vision binary location: ~/.local/bin/vision (or system PATH)"
    audit "WARN: vision binary not found — MCP servers will be non-functional"
    # Non-fatal: installer continues, MCP servers will fail until Vision is installed
    exit 0
fi

_vision_path=$(command -v vision)
ok "vision binary found: $_vision_path"
audit "vision binary: $_vision_path"

# ─── Step 2: Ensure config directory exists ───────────────────────────────────
step "Ensuring Vision config directory"
mkdir -p "$VISION_CONFIG_DIR" || {
    error "Cannot create Vision config dir: $VISION_CONFIG_DIR"
    exit 1
}
ok "Vision config dir: $VISION_CONFIG_DIR"

# ─── Step 3: Ensure servers.yaml exists (atomic secure creation) ─────────────
# servers.yaml may contain API keys — must be owner-only from creation.
# Use install -m 0600 to create with correct perms atomically (no chmod race).
step "Checking servers.yaml"
if [ ! -f "$VISION_YAML" ]; then
    step "Creating initial servers.yaml"
    install -m 0600 /dev/null "$VISION_YAML" || {
        error "Cannot create $VISION_YAML with 0600 permissions"
        exit 1
    }
    cat > "$VISION_YAML" <<'YAML'
# Vision Server Registry — managed by open-chad
# Add your own servers below. open-chad entries are marked with # open-chad
servers: {}
YAML
    ok "Created: $VISION_YAML"
    audit "Created servers.yaml (0600)"
else
    # Existing file — ensure perms are correct (may have been loosened)
    chmod 0600 "$VISION_YAML" || {
        error "Cannot set 0600 permissions on $VISION_YAML"
        exit 1
    }
fi
ok "servers.yaml permissions: 0600"
audit "servers.yaml perms verified"

# ─── Step 5: Register open-chad MCP servers (idempotent) ─────────────────────
# Each server is only added if not already present (key-based check).
# We use a simple grep check — if the server key exists, skip it.
# This preserves user customizations and avoids duplicate entries.

step "Registering open-chad MCP servers"

_register_server() {
    local key="$1"
    local port="$2"
    local entry="$3"

    if grep -qE "^  ${key}:[[:space:]]*(#.*)?$" "$VISION_YAML" 2>/dev/null; then
        ok "$key already registered (port $port)"
        audit "SKIP: $key already in servers.yaml"
        return 0
    fi

    # Append the server entry to servers.yaml
    # If the file ends with 'servers: {}', replace that with 'servers:' first
    if grep -q "^servers: {}" "$VISION_YAML" 2>/dev/null; then
        local _tmp
        _tmp=$(mktemp)
        sed 's/^servers: {}$/servers:/' "$VISION_YAML" > "$_tmp"
        mv -f "$_tmp" "$VISION_YAML"
        chmod 0600 "$VISION_YAML"
    fi

    # Append entry
    printf '\n%s\n' "$entry" >> "$VISION_YAML"
    ok "$key registered (port $port)"
    audit "Registered: $key on port $port"
}

# context7 — Library/API documentation
_register_server "context7" "6276" \
'  context7:  # open-chad
    port: 6276
    command: npx
    args:
      - "-y"
      - "@upstash/context7-mcp@latest"
    autostart: true
    source: https://github.com/upstash/context7'

# grep-app — Code search across GitHub
_register_server "grep-app" "6288" \
'  grep-app:  # open-chad
    port: 6288
    command: npx
    args:
      - "-y"
      - "@grep-app/mcp@latest"
    autostart: true
    source: https://grep.app'

# lgrep — Semantic local code search
_register_server "lgrep" "6285" \
'  lgrep:  # open-chad
    port: 6285
    command: npx
    args:
      - "-y"
      - "@lgrep/mcp@latest"
    autostart: true
    source: https://github.com/anomalyco/lgrep'

# firecrawl — Web scraping (enabled by default for Scout agent)
_register_server "firecrawl" "6281" \
'  firecrawl:  # open-chad
    port: 6281
    command: npx
    args:
      - "-y"
      - "@mendableai/firecrawl-mcp@latest"
    autostart: true
    source: https://github.com/mendableai/firecrawl'

# ─── Step 6: Reload daemon if running ────────────────────────────────────────
step "Checking Vision daemon"
if vision daemon status 2>/dev/null | grep -q "running"; then
    step "Reloading Vision daemon to pick up new server entries"
    if vision daemon reload 2>/dev/null; then
        ok "Vision daemon reloaded"
        audit "Daemon reloaded"
    else
        warn "vision daemon reload failed — restart Vision manually if needed"
        audit "WARN: daemon reload failed"
    fi
else
    ok "Vision daemon not running — will start on next openchad launch"
    audit "Daemon not running at setup time"
fi

# ─── Done ─────────────────────────────────────────────────────────────────────
audit "setup_vision.sh complete"
ok "Vision setup complete."
echo ""
echo -e "  ${C_SAGE}Registered:${C_RESET} context7 (6276), grep-app (6288), lgrep (6285), firecrawl (6281)"
