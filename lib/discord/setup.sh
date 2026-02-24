#!/usr/bin/env bash
# lib/discord/setup.sh — Discord Rich Presence wizard + CLI subcommands
#
# Subcommands (invoked via open-chad discord <subcommand>):
#   enable      — First-run wizard (or re-enable). Validates CLIENT_ID, writes config.
#   disable     — Sets discordPresence.enabled=false in config.
#   status      — Shows current configuration state.
#
# Internal flags (for testing without interactive prompts):
#   --enable   --no-prompt   DISCORD_CLIENT_ID=<id>   (non-interactive enable)
#   --disable                                          (non-interactive disable)
#   --status                                           (show status)
#   --validate-id            DISCORD_CLIENT_ID=<id>   (validate and print result)
#
# Environment overrides:
#   OPEN_CHAD_CONFIG_FILE   — path to config JSON (default: ~/.config/opencode/open-chad.json)
#   DISCORD_CLIENT_ID       — client ID (used only in non-interactive --enable --no-prompt mode)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─── Colors ──────────────────────────────────────────────────────────────────

C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_RESET="\e[0m"

# ─── Config path ─────────────────────────────────────────────────────────────

if [ -n "${OPEN_CHAD_CONFIG_FILE:-}" ]; then
    CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE"
else
    CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json"
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────

# Validate Discord CLIENT_ID format: 17-20 digits
validate_client_id() {
    local id="$1"
    if [[ "$id" =~ ^[0-9]{17,20}$ ]]; then
        echo "valid"
        return 0
    else
        echo "invalid: must be 17-20 digit number (got: $id)"
        return 1
    fi
}

# Read a value from the JSON config
config_get() {
    local field="$1"
    if [ ! -f "$CONFIG_FILE" ]; then echo ""; return; fi
    node -e "
try {
  const fs=require('fs');
  const c=JSON.parse(fs.readFileSync('$CONFIG_FILE','utf8'));
  const val=$field;
  process.stdout.write(val===undefined||val===null?'':String(val));
} catch(e){ process.stdout.write(''); }
" 2>/dev/null || echo ""
}

# Merge a JSON patch into the config file (idempotent)
config_set() {
    local patch="$1"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    node -e "
const fs=require('fs');
let existing={};
try { existing=JSON.parse(fs.readFileSync('$CONFIG_FILE','utf8')); } catch(e){}
const patch=$patch;
// Deep merge: for discordPresence, merge the sub-object
if (patch.discordPresence && existing.discordPresence) {
  patch.discordPresence = Object.assign({}, existing.discordPresence, patch.discordPresence);
}
const merged=Object.assign({}, existing, patch);
fs.writeFileSync('$CONFIG_FILE', JSON.stringify(merged, null, 2) + '\n');
" 2>/dev/null
}

# ─── Subcommands ─────────────────────────────────────────────────────────────

cmd_validate_id() {
    local id="${DISCORD_CLIENT_ID:-}"
    if [ -z "$id" ]; then
        echo "error: DISCORD_CLIENT_ID is not set"
        exit 1
    fi
    local result
    result=$(validate_client_id "$id")
    echo "$result"
    if [[ "$result" == "valid" ]]; then exit 0; else exit 1; fi
}

cmd_enable() {
    local no_prompt="${1:-0}"
    local client_id="${DISCORD_CLIENT_ID:-}"

    if [ "$no_prompt" = "0" ]; then
        # Interactive wizard
        echo -e "\n${C_SAGE}╔══════════════════════════════════════╗${C_RESET}"
        echo -e "${C_SAGE}║  Discord Rich Presence — Setup       ║${C_RESET}"
        echo -e "${C_SAGE}╚══════════════════════════════════════╝${C_RESET}\n"
        echo -e "This will show your open-chad activity on Discord."
        echo -e "See ${C_GOLD}lib/discord/SETUP.md${C_RESET} for how to create a Discord app.\n"

        while true; do
            read -r -p "Enter your Discord Application ID (Client ID): " client_id
            local validation_result
            validation_result=$(validate_client_id "$client_id") || true
            if [[ "$validation_result" == "valid" ]]; then
                break
            else
            echo -e "${C_CORAL}  $validation_result${C_RESET}"
            fi
        done
    else
        # Non-interactive: CLIENT_ID from environment
        if [ -z "$client_id" ]; then
            echo "error: DISCORD_CLIENT_ID must be set for --no-prompt mode"
            exit 1
        fi
        local validation_result
        validation_result=$(validate_client_id "$client_id") || true
        if [[ "$validation_result" != "valid" ]]; then
            echo "error: $validation_result"
            exit 1
        fi
    fi

    # Write config
    config_set "{\"discordPresence\":{\"enabled\":true,\"clientId\":\"$client_id\"}}"

    if [ "$no_prompt" = "0" ]; then
        echo -e "\n${C_SAGE}✓ Discord Rich Presence enabled!${C_RESET}"
        echo -e "  Client ID: ${C_GOLD}$client_id${C_RESET}"
        echo -e "  Config:    ${C_GOLD}$CONFIG_FILE${C_RESET}"
        echo -e "\nPresence will update next time you start open-chad.\n"
    fi
}

cmd_disable() {
    if [ ! -f "$CONFIG_FILE" ]; then
        # Config doesn't exist — already effectively disabled
        exit 0
    fi

    config_set '{"discordPresence":{"enabled":false}}'

    if [ "${1:-}" != "--quiet" ]; then
        echo -e "${C_GOLD}Discord Rich Presence disabled.${C_RESET}"
        echo -e "Re-enable with: ${C_SAGE}open-chad discord enable${C_RESET}"
    fi
}

cmd_status() {
    local enabled
    enabled=$(config_get "(c.discordPresence||{}).enabled||false")
    local client_id
    client_id=$(config_get "(c.discordPresence||{}).clientId||''")
    local lock_file="${OPEN_CHAD_DISCORD_LOCK:-/tmp/discord-rpc.lock}"

    echo -e "\n${C_SAGE}Discord Rich Presence Status${C_RESET}"
    echo -e "──────────────────────────────────────"

    if [ "$enabled" = "true" ]; then
        echo -e "  Status:    ${C_SAGE}enabled${C_RESET}"
        echo -e "  Client ID: ${C_GOLD}${client_id:-not set}${C_RESET}"
    else
        echo -e "  Status:    ${C_CORAL}disabled${C_RESET}"
        echo -e "  Run ${C_GOLD}open-chad discord enable${C_RESET} to set up."
    fi

    if [ -f "$lock_file" ]; then
        local last_update
        last_update=$(date -r "$lock_file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        echo -e "  Last update: $last_update"
    fi

    local log_file="${TMPDIR:-/tmp}/open-chad-discord.log"
    if [ -f "$log_file" ]; then
        echo -e "  Debug log: ${C_GOLD}$log_file${C_RESET}"
    fi

    echo -e "  Config:    ${C_GOLD}$CONFIG_FILE${C_RESET}\n"
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

NO_PROMPT=0

case "${1:-}" in
    --validate-id)
        cmd_validate_id
        ;;
    --enable)
        shift
        if [ "${1:-}" = "--no-prompt" ]; then
            NO_PROMPT=1
        fi
        cmd_enable "$NO_PROMPT"
        ;;
    --disable)
        cmd_disable
        ;;
    --status)
        cmd_status
        ;;
    enable)
        cmd_enable 0
        ;;
    disable)
        cmd_disable
        ;;
    status)
        cmd_status
        ;;
    "")
        # Default: interactive wizard (same as enable)
        cmd_enable 0
        ;;
    *)
        echo "Usage: open-chad discord {enable|disable|status}" >&2
        exit 1
        ;;
esac
