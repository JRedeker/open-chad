#!/usr/bin/env bash
# lib/openchad_metrics.sh — openchad metrics subcommand handler
#
# Subcommands:
#   openchad metrics log     — append timestamped reading to metrics history file
#   openchad metrics export  — print current metrics as JSON
#   openchad metrics show    — print current metrics in human-readable form (default)
#
# Called by: bin/openchad metrics [log|export|show]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Resolve cache directory
# shellcheck source=Claude_env.sh
if [ -f "$REPO_DIR/lib/Claude_env.sh" ]; then
    source "$REPO_DIR/lib/Claude_env.sh"
fi
CACHE_DIR="${OPEN_CHAD_CACHE_DIR:-/tmp/open-chad-${USER:-unknown}}"
METRICS_FILE="$CACHE_DIR/metrics"
METRICS_HISTORY="$CACHE_DIR/metrics_history.log"

_subcommand="${1:-show}"
shift || true

_read_metrics() {
    if [ -f "$METRICS_FILE" ]; then
        read -r _cpu _ram _load < "$METRICS_FILE" 2>/dev/null || true
        echo "${_cpu:-0} ${_ram:-0} ${_load:-0.00}"
    else
        echo "0 0 0.00"
    fi
}

case "$_subcommand" in
    log)
        # Append timestamped reading to history file
        _vals=$(_read_metrics)
        read -r _cpu _ram _load <<< "$_vals"
        _ts=$(date -Iseconds)
        echo "$_ts cpu=${_cpu}% ram=${_ram}% load=${_load}" >> "$METRICS_HISTORY"
        echo "Logged: $_ts cpu=${_cpu}% ram=${_ram}% load=${_load}"
        ;;
    export)
        # Print current metrics as JSON
        _vals=$(_read_metrics)
        read -r _cpu _ram _load <<< "$_vals"
        _ts=$(date -Iseconds)
        printf '{"timestamp":"%s","cpu_percent":%s,"ram_percent":%s,"load_avg":"%s"}\n' \
            "$_ts" "$_cpu" "$_ram" "$_load"
        ;;
    show|*)
        # Human-readable current metrics
        _vals=$(_read_metrics)
        read -r _cpu _ram _load <<< "$_vals"
        echo "openchad metrics (from $METRICS_FILE):"
        echo "  CPU:  ${_cpu}%"
        echo "  RAM:  ${_ram}%"
        echo "  Load: ${_load}"
        if [ -f "$METRICS_HISTORY" ]; then
            echo ""
            echo "History log: $METRICS_HISTORY ($(wc -l < "$METRICS_HISTORY") entries)"
        fi
        ;;
esac
