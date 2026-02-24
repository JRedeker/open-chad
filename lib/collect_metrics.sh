#!/usr/bin/env bash
# open-chad: Shared system metrics collector (singleton)
# Writes CPU%, RAM%, load to /tmp/open-chad-metrics every 30s
# Writes LLM fuel% to /tmp/open-chad-llm-metrics every 30s
# Designed for 10+ concurrent tmux sessions reading the same cache

set -euo pipefail

# --- LLM Fuel Gauge configuration ---
# Token limit for the 5-hour rolling window (community-derived, approximate).
# Anthropic's actual enforcement unit is messages, not tokens.
# Pro plan:   ~44,000 tokens per 5-hour window
# Max5 plan:  ~88,000 tokens per 5-hour window
# Max20 plan: ~220,000 tokens per 5-hour window
PLAN_LIMIT=44000

OPENCODE_DB="${HOME}/.local/share/opencode/opencode.db"
OPENCODE_MSG_DIR="${HOME}/.local/share/opencode/storage/message"
LLM_CACHE="/tmp/open-chad-llm-metrics"
CACHE="/tmp/open-chad-metrics"
LOCKFILE="/tmp/open-chad-metrics.lock"
INTERVAL=30

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

# Returns token usage for last 5 hours via SQLite (fastest path)
# Outputs integer token count, or empty string on failure
_query_tokens_sqlite() {
    local cutoff_ms now_ms
    now_ms=$(date +%s%3N)
    cutoff_ms=$(( now_ms - 5 * 60 * 60 * 1000 ))
    sqlite3 "$OPENCODE_DB" \
        "SELECT COALESCE(SUM(json_extract(data, '$.tokens.total')), 0)
         FROM message
         WHERE json_extract(data, '$.role') = 'assistant'
           AND time_created > ${cutoff_ms}
           AND json_extract(data, '$.tokens.total') > 0;" \
        2>/dev/null
}

# Returns token usage for last 5 hours via jq + JSON files (fallback)
# Uses time.created field (ms epoch) inside each JSON — NOT file mtime
# Outputs integer token count, or empty string on failure
_query_tokens_jq() {
    [ -d "$OPENCODE_MSG_DIR" ] || return 0
    local cutoff_ms now_ms
    now_ms=$(date +%s%3N)
    cutoff_ms=$(( now_ms - 5 * 60 * 60 * 1000 ))
    find "$OPENCODE_MSG_DIR" -type f -name "msg_*.json" \
        | xargs cat 2>/dev/null \
        | jq -s "[.[] \
              | select(.role == \"assistant\" and .time.created > ${cutoff_ms}) \
              | .tokens \
              | select(. != null) \
              | (.input // 0) + (.output // 0) + (.reasoning // 0) \
                + (.cache.read // 0) + (.cache.write // 0)] \
              | add // 0" \
        2>/dev/null
}

collect_llm_fuel() {
    local fuel_pct=100
    local used_tokens=0

    # Try SQLite first (fast: single DB query), fall back to jq+JSON (slower: file scan)
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$OPENCODE_DB" ]; then
        used_tokens=$(_query_tokens_sqlite) || used_tokens=0
    elif command -v jq >/dev/null 2>&1 && [ -d "$OPENCODE_MSG_DIR" ]; then
        used_tokens=$(_query_tokens_jq) || used_tokens=0
    fi

    # Sanitize: must be a non-negative integer
    if ! [[ "${used_tokens:-0}" =~ ^[0-9]+$ ]]; then
        used_tokens=0
    fi

    # Compute remaining fuel percentage, clamped to [0, 100]
    if [ "${used_tokens:-0}" -ge "$PLAN_LIMIT" ]; then
        fuel_pct=0
    elif [ "$PLAN_LIMIT" -gt 0 ]; then
        fuel_pct=$(( 100 - (used_tokens * 100 / PLAN_LIMIT) ))
        [ "$fuel_pct" -lt 0 ] && fuel_pct=0
        [ "$fuel_pct" -gt 100 ] && fuel_pct=100
    fi

    # Atomic write
    local tmp="${LLM_CACHE}.$$"
    printf '%d' "$fuel_pct" > "$tmp"
    mv -f "$tmp" "$LLM_CACHE"
}

while true; do
    collect
    collect_llm_fuel
    sleep "$INTERVAL"
done
