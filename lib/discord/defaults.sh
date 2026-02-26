#!/usr/bin/env bash
# lib/discord/defaults.sh — Single source of truth for Discord Rich Presence defaults
#
# Sourced by lib/discord/setup.sh and lib/discord/update.sh.
# Do NOT add logic here — constants only.
#

# The official openchad Discord Application ID.
# All users who run `openchad discord enable` (without --custom) share this app.
DISCORD_DEFAULT_CLIENT_ID="${DISCORD_DEFAULT_CLIENT_ID:-1476685752363516135}"

# _resolve_discord_client_id <config_file>
#
# Resolves the Discord Client ID to use, with fallback chain:
#   1. User-configured discordPresence.clientId (if set in config)  → mode: custom
#   2. Built-in DISCORD_DEFAULT_CLIENT_ID constant                  → mode: default
#
# Outputs: "<mode> <client_id>"  (space-separated, one line)
# Returns 0 always (non-fatal).
#
# Usage:
#   result=$(_resolve_discord_client_id "$CONFIG_FILE")
#   mode=$(echo "$result" | cut -d" " -f1)   # "custom" or "default"
#   client_id=$(echo "$result" | cut -d" " -f2)
_resolve_discord_client_id() {
    local config_file="${1:-}"
    local user_id=""

    if [ -f "$config_file" ]; then
        user_id=$(node -e "
try {
  const fs=require('fs');
  const c=JSON.parse(fs.readFileSync('$config_file','utf8'));
  const id=(c.discordPresence||{}).clientId||'';
  process.stdout.write(id);
} catch(e){ process.stdout.write(''); }
" 2>/dev/null || true)
    fi

    if [ -n "$user_id" ]; then
        echo "custom $user_id"
    else
        echo "default $DISCORD_DEFAULT_CLIENT_ID"
    fi
}
