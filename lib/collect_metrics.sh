#!/usr/bin/env bash
# open-chad: Shared system metrics collector (singleton)
# Writes CPU%, RAM%, load to /tmp/open-chad-metrics every 30s
# Designed for 10+ concurrent tmux sessions reading the same cache

set -euo pipefail

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

while true; do
    collect
    sleep "$INTERVAL"
done
