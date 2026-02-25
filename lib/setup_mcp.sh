#!/usr/bin/env bash
# lib/setup_mcp.sh — Wire MCP servers into ~/.config/opencode/opencode.json
#
# MCP servers configured:
#   context7       (enabled)  — Library and API documentation
#   grep-app       (enabled)  — Code search across GitHub
#   lgrep          (enabled)  — Semantic local code search
#   firecrawl      (disabled) — Web scraping (vision-managed; enable via vision_add)
#   brave-web-search (disabled) — Web search (requires BRAVE_API_KEY; key-required)
#
# NOTE: opencode.json has NO per-server tool restriction field. Tool filtering
# for firecrawl and brave-web-search is handled via wizard fallback instructions
# and the vision server manager — not via config.
#
# Environment overrides:
#   OPENCODE_CONFIG_DIR  — opencode config dir (default: ~/.config/opencode)
#   OPEN_CHAD_INSTALL_LOG — log file path (default: /tmp/open-chad-install.log)
#
# Called by wizard.sh and install.sh --yes. Safe to call standalone.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

step()  { echo -e "${C_GOLD}[mcp]${C_RESET} $*"; }
ok()    { echo -e "${C_SAGE}[mcp] OK:${C_RESET} $*"; }
warn()  { echo -e "${C_CORAL}[mcp] WARN:${C_RESET} $*"; }
error() { echo -e "${C_CORAL}[mcp] ERROR:${C_RESET} $*" >&2; }
hint()  { echo -e "${C_CORAL}       ↳${C_RESET} $*" >&2; }
audit() { echo "[$(date -Iseconds)] MCP: $*" >> "$INSTALL_LOG"; }

# ─── Configuration ────────────────────────────────────────────────────────────
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_JSON="$OPENCODE_CONFIG_DIR/opencode.json"
INSTALL_LOG="${OPEN_CHAD_INSTALL_LOG:-/tmp/open-chad-install.log}"

# ─── Dependency checks ────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
    error "node not found in PATH. Cannot merge MCP config."
    hint "Install Node.js and re-run: bash $REPO_DIR/lib/setup_ubuntu_deps.sh"
    exit 1
fi

# ─── Ensure opencode.json exists and is valid JSON ────────────────────────────
mkdir -p "$OPENCODE_CONFIG_DIR"

if [ ! -f "$OPENCODE_JSON" ]; then
    step "Creating $OPENCODE_JSON (empty config)"
    echo '{}' > "$OPENCODE_JSON"
    ok "Created empty opencode.json"
fi

# Validate existing JSON before merge
_validate_json() {
    local file="$1"
    node -e "
try {
    const fs = require('fs');
    JSON.parse(fs.readFileSync('$file', 'utf8'));
    process.exit(0);
} catch(e) {
    process.stderr.write('JSON parse error: ' + e.message + '\n');
    process.exit(1);
}
" 2>&1
}

_json_valid_output=$(_validate_json "$OPENCODE_JSON" 2>&1) || {
    error "opencode.json is not valid JSON: $_json_valid_output"
    hint "File: $OPENCODE_JSON"
    hint "Fix the JSON manually or delete the file to start fresh."
    exit 1
}
ok "opencode.json is valid JSON"

# ─── json_merge wrapper with error handling ───────────────────────────────────
_merge() {
    local label="$1"
    local patch="$2"
    audit "Merging $label: $patch"

    local merge_exit=0
    bash "$REPO_DIR/lib/json_merge.sh" "$OPENCODE_JSON" "$patch" 2>>"$INSTALL_LOG" || merge_exit=$?
    if [ "$merge_exit" -ne 0 ]; then
        error "json_merge.sh failed for: $label (exit $merge_exit)"
        hint "Check $INSTALL_LOG for details."
        hint "Patch attempted: $patch"
        exit 1
    fi

    # Validate after each merge to catch corruption early
    _post_valid=$(_validate_json "$OPENCODE_JSON" 2>&1) || {
        error "opencode.json became invalid JSON after merging: $label"
        hint "Post-merge validation error: $_post_valid"
        hint "Restore from backup or delete $OPENCODE_JSON and re-run."
        exit 1
    }

    audit "Merged OK: $label"
}

# ─── MCP server definitions ───────────────────────────────────────────────────
step "Wiring MCP servers into $OPENCODE_JSON"

# context7 — enabled — Library/API docs
_merge "context7" '{
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@upstash/context7-mcp@latest"],
      "enabled": true
    }
  }
}'
ok "context7 (enabled)"
audit "context7 registered"

# grep-app — enabled — Code search
_merge "grep-app" '{
  "mcp": {
    "grep-app": {
      "type": "local",
      "command": ["npx", "-y", "@codarrior/grep-app-mcp@latest"],
      "enabled": true
    }
  }
}'
ok "grep-app (enabled)"
audit "grep-app registered"

# lgrep — enabled — Semantic local search
_merge "lgrep" '{
  "mcp": {
    "lgrep": {
      "type": "local",
      "command": ["npx", "-y", "@codarrior/lgrep-mcp@latest"],
      "enabled": true
    }
  }
}'
ok "lgrep (enabled)"
audit "lgrep registered"

# firecrawl — disabled — Vision-managed web scraper
# Registered but disabled: user enables via `vision_add firecrawl`
_merge "firecrawl" '{
  "mcp": {
    "firecrawl": {
      "type": "local",
      "command": ["npx", "-y", "firecrawl-mcp@latest"],
      "enabled": false
    }
  }
}'
ok "firecrawl (disabled — enable via: vision_add firecrawl)"
audit "firecrawl registered (disabled)"

# brave-web-search — disabled — Requires BRAVE_API_KEY
_merge "brave-web-search" '{
  "mcp": {
    "brave-web-search": {
      "type": "local",
      "command": ["npx", "-y", "@modelcontextprotocol/server-brave-search@latest"],
      "enabled": false
    }
  }
}'
ok "brave-web-search (disabled — requires BRAVE_API_KEY env var)"
audit "brave-web-search registered (disabled, key-required)"

# ─── Final validation ─────────────────────────────────────────────────────────
step "Validating final opencode.json"
_final_valid=$(_validate_json "$OPENCODE_JSON" 2>&1) || {
    error "opencode.json is invalid JSON after all MCP merges!"
    hint "Parse error: $_final_valid"
    hint "File: $OPENCODE_JSON"
    exit 1
}

# Verify all 5 servers are present in the output
_servers_ok=1
for server in context7 grep-app lgrep firecrawl brave-web-search; do
    if node -e "
const fs=require('fs');
const c=JSON.parse(fs.readFileSync('$OPENCODE_JSON','utf8'));
process.exit((c.mcp && c.mcp['$server']) ? 0 : 1);
" 2>/dev/null; then
        : # present
    else
        error "Server '$server' is missing from opencode.json after merge!"
        _servers_ok=0
    fi
done

if [ "$_servers_ok" -eq 0 ]; then
    exit 1
fi

audit "All 5 MCP servers verified in opencode.json"
ok "MCP setup complete. 5 servers registered (3 enabled, 2 disabled)."
echo ""
echo -e "  ${C_SAGE}Enabled:${C_RESET}  context7, grep-app, lgrep"
echo -e "  ${C_GOLD}Disabled:${C_RESET} firecrawl (vision_add firecrawl), brave-web-search (needs API key)"
