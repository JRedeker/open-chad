#!/usr/bin/env bash
# lib/discord/update.sh — Rate-limited Discord Rich Presence bridge
#
# Usage: bash lib/discord/update.sh <session_count> [elapsed_seconds]
#
# Reads config from OPEN_CHAD_CONFIG_FILE (or ~/.config/opencode/open-chad.json).
# Rate-limits updates to 1 per 15 seconds via /tmp/discord-rpc.lock mtime.
# Exits silently (exit 0) if:
#   - discordPresence.enabled is false or missing
#   - Rate limit has not elapsed
#   - Discord is not running (handled by update.js)
#   - Any error occurs
#
# Environment overrides (for testing):
#   OPEN_CHAD_CONFIG_FILE   — path to config JSON
#   DISCORD_RATE_LIMIT_SEC  — rate limit in seconds (default: 15)
#   OPEN_CHAD_DISCORD_LOCK  — path to lockfile (default: /tmp/discord-rpc.lock)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Resolve dedicated cache directory (XDG_RUNTIME_DIR/open-chad or /tmp/open-chad-$USER)
# shellcheck source=../opencode_env.sh
source "$REPO_DIR/lib/opencode_env.sh"

# Single source of truth for default Client ID and resolution helper
# shellcheck source=lib/discord/defaults.sh
source "$SCRIPT_DIR/defaults.sh"

# ─── Config ──────────────────────────────────────────────────────────────────

RATE_LIMIT_SEC="${DISCORD_RATE_LIMIT_SEC:-15}"
LOCK_FILE="${OPEN_CHAD_DISCORD_LOCK:-${OPEN_CHAD_CACHE_DIR}/discord-rpc.lock}"
GUARD_FILE="${LOCK_FILE}.guard"

# Resolve config file: env override → default location
if [ -n "${OPEN_CHAD_CONFIG_FILE:-}" ]; then
    CONFIG_FILE="$OPEN_CHAD_CONFIG_FILE"
else
    CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json"
fi

# ─── Helpers ─────────────────────────────────────────────────────────────────

log_debug() {
    [ "${OPEN_CHAD_DEBUG:-0}" = "1" ] && echo "[open-chad-discord] $*" >&2 || true
}

# Read a JSON field using node (already a hard dep)
# Usage: json_get <file> <field_path>  e.g. json_get config.json ".discordPresence.enabled"
json_get() {
    local file="$1" field="$2"
    node -e "
try {
  const fs=require('fs');
  const c=JSON.parse(fs.readFileSync('$file','utf8'));
  const val=$field;
  process.stdout.write(val===undefined||val===null?'':String(val));
} catch(e){ process.stdout.write(''); }
" 2>/dev/null || true
}

# ─── Main ────────────────────────────────────────────────────────────────────

main() {
    local session_count="${1:-1}"
    local elapsed_seconds="${2:-0}"

    # 1. Check config exists
    if [ ! -f "$CONFIG_FILE" ]; then
        log_debug "config file not found: $CONFIG_FILE — skipping"
        exit 0
    fi

    # 2. Check discordPresence.enabled
    local enabled
    enabled=$(json_get "$CONFIG_FILE" "c.discordPresence && c.discordPresence.enabled")
    if [ "$enabled" != "true" ]; then
        log_debug "discordPresence not enabled — skipping"
        exit 0
    fi

    # 3. Resolve CLIENT_ID via fallback chain:
    #    user-configured clientId → built-in DISCORD_DEFAULT_CLIENT_ID
    local resolve_result mode client_id
    resolve_result=$(_resolve_discord_client_id "$CONFIG_FILE")
    mode=$(echo "$resolve_result" | cut -d" " -f1)
    client_id=$(echo "$resolve_result" | cut -d" " -f2)
    log_debug "client_id resolved: mode=$mode id=$client_id"

    # 4. Rate limit check via lockfile mtime
    # Wrapped in flock to prevent concurrent race where two update.sh calls
    # both pass the mtime check before either touches the lockfile (SC-mHX0zSLG)
    if command -v flock &>/dev/null; then
        # Atomic: acquire exclusive lock on guard file, then check + update mtime
        (
            flock -n 9 || { log_debug "lock held by concurrent update — skipping"; exit 0; }
            if [ -f "$LOCK_FILE" ]; then
                lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
                now_ts=$(date +%s)
                elapsed_since=$(( now_ts - lock_mtime ))
                if [ "$elapsed_since" -lt "$RATE_LIMIT_SEC" ]; then
                    log_debug "rate limited (${elapsed_since}s < ${RATE_LIMIT_SEC}s) — skipping"
                    exit 0
                fi
            fi
            touch "$LOCK_FILE" 2>/dev/null || true
        ) 9>"$GUARD_FILE" || exit 0
    else
        # flock not available (macOS without brew util-linux): plain mtime check
        if [ -f "$LOCK_FILE" ]; then
            lock_mtime=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
            now_ts=$(date +%s)
            elapsed_since=$(( now_ts - lock_mtime ))
            if [ "$elapsed_since" -lt "$RATE_LIMIT_SEC" ]; then
                log_debug "rate limited (${elapsed_since}s < ${RATE_LIMIT_SEC}s) — skipping"
                exit 0
            fi
        fi
        touch "$LOCK_FILE" 2>/dev/null || true
    fi

    # 5. Pick tagline (sourced from taglines.sh)
    local tagline="Chadding hard"
    if [ -f "$SCRIPT_DIR/taglines.sh" ]; then
        # shellcheck source=lib/discord/taglines.sh
        tagline=$(bash "$SCRIPT_DIR/taglines.sh" 2>/dev/null || echo "Chadding hard")
    fi

    # 6. Touch lockfile BEFORE spawning node (prevents double-fire on concurrent calls)
    touch "$LOCK_FILE" 2>/dev/null || true

    # 7. Invoke update.js (exits 0 on Discord-not-running per SC-10)
    DISCORD_CLIENT_ID="$client_id" \
        node "$REPO_DIR/lib/discord/update.js" \
            "$session_count" "$elapsed_seconds" "$tagline" \
        2>/dev/null || true

    log_debug "update.js completed"
}

main "$@"
