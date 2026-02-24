#!/usr/bin/env bash
# lib/discord/taglines.sh — Rotating tagline selector with no-repeat guard
#
# Outputs one tagline to stdout. Uses a /tmp statefile to avoid repeating
# the same tagline on consecutive calls.
#
# Usage: bash lib/discord/taglines.sh
# Output: a single tagline string (no newline at end for clean assignment)

set -uo pipefail

TAGLINES=(
    "Chadding hard"
    "AI chaos coordination"
    "Vim motions engaged"
    "Making it rain tokens"
    "Deploying the bots"
    "Ship it, ship it good"
    "Agents on the loose"
    "Context window loading"
    "Peak developer mode"
    "Summoning the models"
    "Going full autonomous"
    "Code velocity: maximum"
    "The machines are working"
    "Parallel minds at work"
    "Unleashing the AI"
)

LAST_TAGLINE_FILE="${OPEN_CHAD_DISCORD_LOCK:-/tmp/discord-rpc.lock}.tagline"
TAGLINE_COUNT=${#TAGLINES[@]}

# Read last index used (if any)
last_idx=-1
if [ -f "$LAST_TAGLINE_FILE" ]; then
    last_idx=$(cat "$LAST_TAGLINE_FILE" 2>/dev/null || echo -1)
fi

# Pick a random index, avoiding the last one used
while true; do
    idx=$(( RANDOM % TAGLINE_COUNT ))
    if [ "$idx" -ne "$last_idx" ] || [ "$TAGLINE_COUNT" -eq 1 ]; then
        break
    fi
done

# Persist the chosen index
echo "$idx" > "$LAST_TAGLINE_FILE" 2>/dev/null || true

# Output the tagline
printf '%s' "${TAGLINES[$idx]}"
