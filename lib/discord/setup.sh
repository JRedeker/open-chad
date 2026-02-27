#!/usr/bin/env bash
# lib/discord/setup.sh — Discord Rich Presence wizard + CLI subcommands
#
# Subcommands (invoked via openchad discord <subcommand>):
#   enable           — Default path: writes enabled=true, no clientId, no prompt.
#   enable --custom  — Interactive wizard: prompts for Client ID, writes clientId.
#   disable          — Sets discordPresence.enabled=false in config.
#   status           — Shows current configuration state (mode: default/custom).
#
# Internal flags (for testing without interactive prompts):
#   --enable   --no-prompt   DISCORD_CLIENT_ID=<id>   (non-interactive custom enable)
#   --disable                                          (non-interactive disable)
#   --status                                           (show status)
#   --validate-id            DISCORD_CLIENT_ID=<id>   (validate and print result)
#
# Environment overrides:
#   OPEN_CHAD_CONFIG_FILE   — path to config JSON (default: ~/.config/opencode/open-chad.json)
#   DISCORD_CLIENT_ID       — client ID (used in --custom --no-prompt mode)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Resolve dedicated cache directory (OPEN_CHAD_CACHE_DIR)
# shellcheck source=../opencode_env.sh
if [ -f "$REPO_DIR/lib/opencode_env.sh" ]; then
    source "$REPO_DIR/lib/opencode_env.sh"
fi

# Single source of truth for default Client ID and resolution helper
# shellcheck source=lib/discord/defaults.sh
source "$SCRIPT_DIR/defaults.sh"

# WSL Discord IPC bridge helper (non-fatal if missing)
# shellcheck source=lib/discord/wsl_bridge.sh
if [ -f "$SCRIPT_DIR/wsl_bridge.sh" ]; then
    source "$SCRIPT_DIR/wsl_bridge.sh"
fi

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

# cmd_enable_default — zero-prompt path
# Writes discordPresence.enabled=true only. No clientId. No prompt.
cmd_enable_default() {
    config_set '{"discordPresence":{"enabled":true}}'
    echo -e "${C_SAGE}✓ Discord Rich Presence enabled (default mode).${C_RESET}"
    echo -e "  Config: ${C_GOLD}$CONFIG_FILE${C_RESET}"
    echo -e "  Run ${C_GOLD}openchad discord status${C_RESET} to verify."
}

# cmd_enable_custom — interactive wizard or non-interactive via env var
# Prompts for Client ID (or reads DISCORD_CLIENT_ID), validates, writes clientId.
# Args: $1 = "1" for --no-prompt (non-interactive), "0" for interactive
cmd_enable_custom() {
    local no_prompt="${1:-0}"
    local client_id="${DISCORD_CLIENT_ID:-}"

    if [ "$no_prompt" = "0" ]; then
        # Interactive wizard
        echo -e "\n${C_SAGE}╔══════════════════════════════════════╗${C_RESET}"
        echo -e "${C_SAGE}║  Discord Rich Presence — Custom App  ║${C_RESET}"
        echo -e "${C_SAGE}╚══════════════════════════════════════╝${C_RESET}\n"
        echo -e "This will use your own Discord Application ID."
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

    # Write config with clientId
    config_set "{\"discordPresence\":{\"enabled\":true,\"clientId\":\"$client_id\"}}"

    if [ "$no_prompt" = "0" ]; then
        echo -e "\n${C_SAGE}✓ Discord Rich Presence enabled (custom mode)!${C_RESET}"
        echo -e "  Client ID: ${C_GOLD}$client_id${C_RESET}"
        echo -e "  Config:    ${C_GOLD}$CONFIG_FILE${C_RESET}"
        echo -e "\nPresence will update next time you start openchad.\n"
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
        echo -e "Re-enable with: ${C_SAGE}openchad discord enable${C_RESET}"
    fi
}

cmd_status() {
    local enabled
    enabled=$(config_get "(c.discordPresence||{}).enabled||false")

    # Resolve Client ID and mode via shared helper (custom → default fallback)
    local resolve_result mode client_id
    resolve_result=$(_resolve_discord_client_id "$CONFIG_FILE")
    mode=$(echo "$resolve_result" | cut -d" " -f1)
    client_id=$(echo "$resolve_result" | cut -d" " -f2)

    # Lock file lives in OPEN_CHAD_CACHE_DIR (not /tmp)
    local cache_dir="${OPEN_CHAD_CACHE_DIR:-${TMPDIR:-/tmp}/open-chad-${USER:-user}}"
    local lock_file="${OPEN_CHAD_DISCORD_LOCK:-${cache_dir}/discord-rpc.lock}"
    local log_file="${cache_dir}/discord.log"

    echo -e "\n${C_SAGE}Discord Rich Presence Status${C_RESET}"
    echo -e "──────────────────────────────────────"

    if [ "$enabled" = "true" ]; then
        echo -e "  Status:    ${C_SAGE}enabled${C_RESET}"
        echo -e "  Mode:      ${C_GOLD}${mode}${C_RESET}"
        if [ "$mode" = "custom" ]; then
            echo -e "  Client ID: ${C_GOLD}${client_id}${C_RESET}"
        fi
    else
        echo -e "  Status:    ${C_CORAL}disabled${C_RESET}"
        echo -e "  Run ${C_GOLD}openchad discord enable${C_RESET} to set up."
    fi

    if [ -f "$lock_file" ]; then
        local last_update
        last_update=$(date -r "$lock_file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
            || stat -c '%y' "$lock_file" 2>/dev/null | cut -d'.' -f1 \
            || echo "unknown")
        echo -e "  Last update: $last_update"
    fi

    if [ -f "$log_file" ]; then
        echo -e "  Debug log: ${C_GOLD}$log_file${C_RESET}"
    fi

    # Bridge status (WSL only — hidden on native Linux)
    if declare -f _wsl_bridge_status &>/dev/null; then
        local bridge_status
        bridge_status=$(_wsl_bridge_status 2>/dev/null || echo "not-wsl")
        case "$bridge_status" in
            not-wsl)
                # Native Linux — hide bridge section entirely
                ;;
            missing-deps)
                # Show which specific dep is missing
                local _socat_path _npiperelay_path
                _socat_path=$(command -v socat 2>/dev/null)
                _npiperelay_path=$(_wsl_bridge_get_npiperelay 2>/dev/null)
                if [ -z "$_socat_path" ]; then
                    echo -e "  Bridge:    ${C_CORAL}missing socat${C_RESET} (install: sudo apt install socat)"
                elif [ -z "$_npiperelay_path" ]; then
                    echo -e "  Bridge:    ${C_CORAL}missing npiperelay.exe${C_RESET}"
                    echo -e "             ${C_GOLD}GOOS=windows GOARCH=amd64 go install github.com/jstarks/npiperelay@latest${C_RESET}"
                else
                    echo -e "  Bridge:    ${C_CORAL}missing deps${C_RESET}"
                fi
                ;;
            not-running)
                local bridge_pid_file="${cache_dir}/discord-bridge.pid"
                echo -e "  Bridge:    ${C_CORAL}not running${C_RESET} (start: openchad discord enable)"
                ;;
            ready)
                local bridge_pid
                bridge_pid=$(cat "${cache_dir}/discord-bridge.pid" 2>/dev/null || echo "?")
                echo -e "  Bridge:    ${C_SAGE}ready${C_RESET} (PID $bridge_pid)"
                ;;
        esac
    fi

    echo -e "  Config:    ${C_GOLD}$CONFIG_FILE${C_RESET}\n"
}

# ─── Argument parsing ─────────────────────────────────────────────────────────

case "${1:-}" in
    --validate-id)
        cmd_validate_id
        ;;
    --enable)
        # Legacy non-interactive flag: --enable [--no-prompt]
        # With --no-prompt + DISCORD_CLIENT_ID → custom non-interactive path
        # Without --no-prompt → default path (no prompt, no clientId)
        shift
        if [ "${1:-}" = "--no-prompt" ]; then
            cmd_enable_custom "1"
        else
            cmd_enable_default
        fi
        ;;
    --disable)
        cmd_disable
        ;;
    --status)
        cmd_status
        ;;
    enable)
        shift
        if [ "${1:-}" = "--custom" ]; then
            shift
            # --custom [--no-prompt]: interactive wizard or non-interactive via env
            if [ "${1:-}" = "--no-prompt" ]; then
                cmd_enable_custom "1"
            else
                cmd_enable_custom "0"
            fi
        else
            # Default enable: no prompt, no clientId
            cmd_enable_default
        fi
        ;;
    disable)
        cmd_disable
        ;;
    status)
        cmd_status
        ;;
    "")
        # Default: same as 'enable' (zero-prompt default path)
        cmd_enable_default
        ;;
    *)
        echo "Usage: openchad discord {enable [--custom]|disable|status}" >&2
        exit 1
        ;;
esac
