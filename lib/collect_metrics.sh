#!/usr/bin/env bash
# open-chad: Shared system metrics collector (singleton)
# Writes CPU%, RAM%, load to $OPEN_CHAD_CACHE_DIR/metrics every 30s
# Writes per-provider LLM quota % to 4 separate cache files every 30s:
#   $OPEN_CHAD_CACHE_DIR/zai, $OPEN_CHAD_CACHE_DIR/copilot,
#   $OPEN_CHAD_CACHE_DIR/claude, $OPEN_CHAD_CACHE_DIR/codex
#
# Multi-provider gauge is opt-in via OPEN_CHAD_MULTI_GAUGE=1 (default: auto)
#   OPEN_CHAD_MULTI_GAUGE=1   → always collect
#   OPEN_CHAD_MULTI_GAUGE=0   → never collect (hides gauge)
#   unset / "auto"            → collect only if ≥1 provider token found in auth.json
#
# Designed for 10+ concurrent tmux sessions reading the same cache

set -euo pipefail

# Resolve dedicated cache directory (XDG_RUNTIME_DIR/open-chad or /tmp/open-chad-$USER)
# shellcheck source=opencode_env.sh
source "$(dirname "${BASH_SOURCE[0]}")/opencode_env.sh"

AUTH_JSON="${HOME}/.local/share/opencode/auth.json"
CACHE="${OPEN_CHAD_CACHE_DIR}/metrics"
LOCKFILE="${OPEN_CHAD_CACHE_DIR}/metrics.lock"
INTERVAL=30

# Per-provider cache files (plain integer 0-100, or empty = unknown)
ZAI_CACHE="${OPEN_CHAD_CACHE_DIR}/zai"
COPILOT_CACHE="${OPEN_CHAD_CACHE_DIR}/copilot"
CLAUDE_CACHE="${OPEN_CHAD_CACHE_DIR}/claude"
CODEX_CACHE="${OPEN_CHAD_CACHE_DIR}/codex"

# Singleton guard: exit if another collector is running
if [ -f "$LOCKFILE" ]; then
    pid=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        exit 0
    fi
    # Stale lock, clean up
    rm -f "$LOCKFILE"
fi

echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# 7-day TTL cleanup: remove stale files from the cache dir.
# Runs once per singleton startup — not on every launcher invocation.
# Wrapped in timeout 5 to prevent hangs on slow or network-mounted filesystems.
# The 2>/dev/null suppresses errors from race-deleted files; || true prevents
# set -e from aborting if find or timeout exits non-zero on a transient ENOENT.
timeout 5 find "${OPEN_CHAD_CACHE_DIR}" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true

collect() {
    # CPU: 1-second sample via /proc/stat (no external tools)
    local cpu1 idle1 cpu2 idle2 cpu_pct
    read -r _ cpu1 _ _ idle1 _ < /proc/stat
    sleep 1
    read -r _ cpu2 _ _ idle2 _ < /proc/stat
    local total_d=$(( (cpu2 + idle2) - (cpu1 + idle1) ))
    local idle_d=$(( idle2 - idle1 ))
    if [ "$total_d" -gt 0 ]; then
        cpu_pct=$(( 100 * (total_d - idle_d) / total_d ))
    else
        cpu_pct=0
    fi

    # RAM: from /proc/meminfo (no external tools)
    local mem_total mem_avail ram_pct
    mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    mem_avail=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    if [ "$mem_total" -gt 0 ]; then
        ram_pct=$(( 100 * (mem_total - mem_avail) / mem_total ))
    else
        ram_pct=0
    fi

    # Load: 1-minute average
    local load
    load=$(cut -d' ' -f1 /proc/loadavg)

    # Atomic write
    local tmp="${CACHE}.$$"
    printf '%s %s %s' "$cpu_pct" "$ram_pct" "$load" > "$tmp"
    mv -f "$tmp" "$CACHE"
}

# Read a key path (e.g. "zai-coding-plan.key") from auth.json
# Outputs the value, or empty string if not found or jq unavailable
_read_auth() {
    local keypath="$1"
    [ -f "$AUTH_JSON" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    # keypath like "zai-coding-plan.key" → .["zai-coding-plan"].key
    local obj key
    obj="${keypath%.*}"
    key="${keypath##*.}"
    jq -r --arg obj "$obj" --arg key "$key" \
        '.[$obj][$key] // empty' "$AUTH_JSON" 2>/dev/null || true
}

# Atomic write of integer to a cache file, or empty string on failure
_write_cache() {
    local cache_file="$1"
    local value="$2"
    local tmp="${cache_file}.$$"
    printf '%s' "$value" > "$tmp"
    mv -f "$tmp" "$cache_file"
}

# Returns 0 (true) if at least one provider token exists in auth.json
# Used for auto-detection when OPEN_CHAD_MULTI_GAUGE is unset
_has_any_provider_token() {
    [ -f "$AUTH_JSON" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    
    # If active_providers exists, only check those tokens
    local active_file="${OPEN_CHAD_CACHE_DIR}/active_providers"
    local jq_filter
    
    if [ -f "$active_file" ]; then
        local keys=()
        while read -r _label cache_key; do
            [ -z "$cache_key" ] && continue
            case "$cache_key" in
                zai)     keys+=('.["zai-coding-plan"].key') ;;
                copilot) keys+=('.["github-copilot"].access') ;;
                claude)  keys+=('.["anthropic"].access') ;;
                codex)   keys+=('.["openai"].access') ;;
            esac
        done < "$active_file"
        
        if [ ${#keys[@]} -eq 0 ]; then
            return 1
        fi
        
        local joined_keys
        joined_keys=$(IFS=,; echo "${keys[*]}")
        jq_filter="[ $joined_keys ] | map(select(. != null and . != \"\")) | length"
    else
        jq_filter='
            [
              .["zai-coding-plan"].key,
              .["github-copilot"].access,
              .["anthropic"].access,
              .["openai"].access
            ] | map(select(. != null and . != "")) | length
        '
    fi
    
    local count
    count=$(jq -r "$jq_filter" "$AUTH_JSON" 2>/dev/null) || return 1
    [ "${count:-0}" -gt 0 ]
}

# Determine whether to run the multi-provider gauge
# Returns 0 (enabled) or 1 (disabled)
_multi_gauge_enabled() {
    local setting="${OPEN_CHAD_MULTI_GAUGE:-auto}"
    case "$setting" in
        1|true|yes|on)   return 0 ;;
        0|false|no|off)  return 1 ;;
        *)  # auto: enable only if at least one token is present
            _has_any_provider_token
            ;;
    esac
}

# Update the active_providers cache file based on open-chad.json
_update_active_providers() {
    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/open-chad.json"
    local active_file="${OPEN_CHAD_CACHE_DIR}/active_providers"
    local tmp="${active_file}.$$"
    
    local providers=""
    if [ -f "$config_file" ] && command -v jq >/dev/null 2>&1; then
        providers=$(jq -r '.providers[]?' "$config_file" 2>/dev/null || true)
    fi
    
    if [ -z "$providers" ]; then
        # Default to all 4
        printf "Z.ai zai\nCopilot copilot\nClaude claude\nCodex codex\n" > "$tmp"
    else
        # Map configured IDs to labels
        for p in $providers; do
            case "$p" in
                zai)     echo "Z.ai zai" >> "$tmp" ;;
                copilot) echo "Copilot copilot" >> "$tmp" ;;
                claude)  echo "Claude claude" >> "$tmp" ;;
                codex)   echo "Codex codex" >> "$tmp" ;;
            esac
        done
    fi
    
    mv -f "$tmp" "$active_file"
}

# Z.ai: GET /api/monitor/usage/quota/limit
# Response: data.limits[type=TOKENS_LIMIT].percentage = used%
# Remaining = 100 - percentage
collect_zai() {
    local api_key
    api_key=$(_read_auth "zai-coding-plan.key")
    if [ -z "$api_key" ]; then
        _write_cache "$ZAI_CACHE" ""
        return 0
    fi

    local response
    response=$(curl -sf --max-time 4 \
        -H "Authorization: Bearer ${api_key}" \
        'https://api.z.ai/api/monitor/usage/quota/limit' 2>/dev/null) || true

    local pct
    pct=$(printf '%s' "$response" | jq -r '
        .data.limits[]
        | select(.type == "TOKENS_LIMIT")
        | .percentage
        | if . == null then empty else (100 - .) | floor end
    ' 2>/dev/null | head -1) || true

    if [[ "${pct:-}" =~ ^[0-9]+$ ]]; then
        _write_cache "$ZAI_CACHE" "$pct"
    else
        _write_cache "$ZAI_CACHE" ""
    fi
}

# GitHub Copilot: GET /copilot_internal/user
# Response: quota_snapshots.premium_interactions.percent_remaining = remaining%
# Value CAN be negative when over quota — clamp to 0
collect_copilot() {
    local token
    token=$(_read_auth "github-copilot.access")
    if [ -z "$token" ]; then
        _write_cache "$COPILOT_CACHE" ""
        return 0
    fi

    local response
    response=$(curl -sf --max-time 4 \
        -H "Authorization: token ${token}" \
        -H "Editor-Version: vscode/1.96.2" \
        -H "Editor-Plugin-Version: copilot-chat/0.26.7" \
        -H "User-Agent: GitHubCopilotChat/0.26.7" \
        'https://api.github.com/copilot_internal/user' 2>/dev/null) || true

    local raw
    raw=$(printf '%s' "$response" | jq -r '
        .quota_snapshots.premium_interactions.percent_remaining
        | if . == null then empty else . end
    ' 2>/dev/null) || true

    if [ -n "$raw" ]; then
        # Clamp to [0, 100] — can be negative when over quota
        local pct
        pct=$(printf '%s' "$raw" | awk '{v=int($1); if(v<0) v=0; if(v>100) v=100; print v}')
        _write_cache "$COPILOT_CACHE" "$pct"
    else
        _write_cache "$COPILOT_CACHE" ""
    fi
}

# Anthropic Claude: GET /api/oauth/usage
# Response: five_hour.utilization = used%
# Remaining = 100 - utilization
collect_claude() {
    local token
    token=$(_read_auth "anthropic.access")
    if [ -z "$token" ]; then
        _write_cache "$CLAUDE_CACHE" ""
        return 0
    fi

    local response
    response=$(curl -sf --max-time 4 \
        -H "Authorization: Bearer ${token}" \
        -H "anthropic-beta: oauth-2025-04-20" \
        'https://api.anthropic.com/api/oauth/usage' 2>/dev/null) || true

    local pct
    pct=$(printf '%s' "$response" | jq -r '
        .five_hour.utilization
        | if . == null then empty else (100 - .) | floor end
    ' 2>/dev/null) || true

    if [[ "${pct:-}" =~ ^[0-9]+$ ]]; then
        _write_cache "$CLAUDE_CACHE" "$pct"
    else
        _write_cache "$CLAUDE_CACHE" ""
    fi
}

# OpenAI Codex: GET chatgpt.com/backend-api/wham/usage
# Response: rate_limit.primary_window.used_percent = used% (5h window)
# Remaining = 100 - used_percent
# Note: use openai.access token (codex.access expires)
collect_codex() {
    local token
    token=$(_read_auth "openai.access")
    if [ -z "$token" ]; then
        _write_cache "$CODEX_CACHE" ""
        return 0
    fi

    local response
    response=$(curl -sf --max-time 4 \
        -H "Authorization: Bearer ${token}" \
        'https://chatgpt.com/backend-api/wham/usage' 2>/dev/null) || true

    local pct
    pct=$(printf '%s' "$response" | jq -r '
        .rate_limit.primary_window.used_percent
        | if . == null then empty else (100 - .) end
    ' 2>/dev/null) || true

    if [[ "${pct:-}" =~ ^[0-9]+$ ]]; then
        _write_cache "$CODEX_CACHE" "$pct"
    else
        _write_cache "$CODEX_CACHE" ""
    fi
}

collect_llm_providers() {
    # Update active providers list first
    _update_active_providers

    # Skip entirely if multi-gauge is disabled or no tokens configured
    if ! _multi_gauge_enabled; then
        return 0
    fi

    local active_file="${OPEN_CHAD_CACHE_DIR}/active_providers"
    local run_zai=0 run_copilot=0 run_claude=0 run_codex=0

    if [ -f "$active_file" ]; then
        while read -r _label cache_key; do
            case "$cache_key" in
                zai)     run_zai=1 ;;
                copilot) run_copilot=1 ;;
                claude)  run_claude=1 ;;
                codex)   run_codex=1 ;;
            esac
        done < "$active_file"
    else
        run_zai=1; run_copilot=1; run_claude=1; run_codex=1
    fi

    # Run selected adapters in parallel with safe wait pattern
    local pid_zai="" pid_copilot="" pid_claude="" pid_codex=""
    
    [ "$run_zai" -eq 1 ]     && { collect_zai     & pid_zai=$!; }
    [ "$run_copilot" -eq 1 ] && { collect_copilot & pid_copilot=$!; }
    [ "$run_claude" -eq 1 ]  && { collect_claude  & pid_claude=$!; }
    [ "$run_codex" -eq 1 ]   && { collect_codex   & pid_codex=$!; }

    local rc_zai=0 rc_copilot=0 rc_claude=0 rc_codex=0
    
    [ -n "$pid_zai" ]     && { wait "$pid_zai"     || rc_zai=$?; }
    [ -n "$pid_copilot" ] && { wait "$pid_copilot" || rc_copilot=$?; }
    [ -n "$pid_claude" ]  && { wait "$pid_claude"  || rc_claude=$?; }
    [ -n "$pid_codex" ]   && { wait "$pid_codex"   || rc_codex=$?; }

    # Log failures to stderr (debug only — not printed in normal operation)
    [ "$rc_zai"     -ne 0 ] && printf 'open-chad: collect_zai failed (rc=%s)\n'     "$rc_zai"     >&2 || true
    [ "$rc_copilot" -ne 0 ] && printf 'open-chad: collect_copilot failed (rc=%s)\n' "$rc_copilot" >&2 || true
    [ "$rc_claude"  -ne 0 ] && printf 'open-chad: collect_claude failed (rc=%s)\n'  "$rc_claude"  >&2 || true
    [ "$rc_codex"   -ne 0 ] && printf 'open-chad: collect_codex failed (rc=%s)\n'   "$rc_codex"   >&2 || true
}

while true; do
    collect
    collect_llm_providers
    sleep "$INTERVAL"
done
