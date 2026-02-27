#!/usr/bin/env bash
# open-chad: Boot animation (official primary agent palette)
# Centered, color-cycling boot sequence
#
# Args: $1 = target directory

set -euo pipefail

TARGET_DIR="${1:-$PWD}"
PROJECT_NAME="$(basename "$TARGET_DIR")"
GIT_BRANCH="$(git -C "$TARGET_DIR" branch --show-current 2>/dev/null || echo "no-branch")"

# Handle interrupts gracefully
trap 'tput cnorm; clear; exit 0' INT TERM

# ═══════════════════════════════════════════════════════════════════════════════
# TERMINAL DIMENSIONS
# ═══════════════════════════════════════════════════════════════════════════════

TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# ═══════════════════════════════════════════════════════════════════════════════
# OFFICIAL PRIMARY AGENT PALETTE (true color)
# ═══════════════════════════════════════════════════════════════════════════════

PALETTE_FILE="$(dirname "${BASH_SOURCE[0]}")/agent_palette.sh"
if [ -f "$PALETTE_FILE" ]; then
    # shellcheck source=/dev/null
    source "$PALETTE_FILE"
fi

C_BUILD="${OPEN_CHAD_ANSI_BUILD:-$'\e[38;2;89;194;255m'}"     # #59C2FF
C_PLAN="${OPEN_CHAD_ANSI_PLAN:-$'\e[38;2;255;180;84m'}"       # #FFB454
C_SCOUT="${OPEN_CHAD_ANSI_SCOUT:-$'\e[38;2;240;113;120m'}"    # #F07178
C_REFINE="${OPEN_CHAD_ANSI_REFINE:-$'\e[38;2;170;217;76m'}"   # #AAD94C
C_COMMENT=$'\e[38;2;98;109;122m'     # #626d7a gray
C_FG=$'\e[38;2;191;189;182m'         # #BFBDB6 foreground
C_RESET=$'\e[0m'

colors=("$C_BUILD" "$C_PLAN" "$C_SCOUT" "$C_REFINE")

# ═══════════════════════════════════════════════════════════════════════════════
# OPEN CHAD LOGO (74 chars wide, 6 lines)
# ═══════════════════════════════════════════════════════════════════════════════

logo=(
    "   ██████╗ ██████╗ ███████╗███╗   ██╗     ██████╗██╗  ██╗█████╗ ██████╗ "
    "  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║    ██╔════╝██║  ██║██╔══██╗██╔══██╗"
    "  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║    ██║     ███████║███████║██║  ██║"
    "  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║    ██║     ██╔══██║██╔══██║██║  ██║"
    "  ╚██████╔╝██║     ███████╗██║ ╚████║    ╚██████╗██║  ██║██║  ██║██████╔╝"
    "   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ "
)

LOGO_WIDTH=74
LOGO_HEIGHT=6

# Calculate center position
LOGO_X=$(( (TERM_WIDTH - LOGO_WIDTH) / 2 ))
LOGO_X=$(( LOGO_X < 0 ? 0 : LOGO_X ))
LOGO_Y=$(( (TERM_HEIGHT - LOGO_HEIGHT - 10) / 2 ))  # -10 for subtitle and context
LOGO_Y=$(( LOGO_Y < 1 ? 1 : LOGO_Y ))

# ═══════════════════════════════════════════════════════════════════════════════
# ANIMATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Draw logo with color offset for cycling effect
draw_logo() {
    local offset="${1:-0}"
    for i in "${!logo[@]}"; do
        local color_idx=$(( (i + offset) % ${#colors[@]} ))
        tput cup $((LOGO_Y + i)) $LOGO_X
        printf "%b%s%b" "${colors[$color_idx]}" "${logo[$i]}" "$C_RESET"
    done
}

# Fast typewriter function
typewriter() {
    local text="$1"
    local color="$2"
    printf "%b" "$color"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep 0.015
    done
    printf "%b" "$C_RESET"
}

# ═══════════════════════════════════════════════════════════════════════════════
# BOOT SEQUENCE
# ═══════════════════════════════════════════════════════════════════════════════

# Hide cursor, clear screen
tput civis
clear

# Phase 1: Color cycling animation (primary palette)
for cycle in {0..3}; do
    draw_logo "$cycle"
    sleep 0.15
done

# Phase 2: Subtitle (centered)
SUBTITLE="O P E N C H A D   1 . 0"
SUBTITLE_X=$(( (TERM_WIDTH - ${#SUBTITLE}) / 2 ))
tput cup $((LOGO_Y + LOGO_HEIGHT + 2)) $SUBTITLE_X
typewriter "$SUBTITLE" "$C_BUILD"

sleep 0.1

# Phase 3: Context info (centered)
INFO_Y=$((LOGO_Y + LOGO_HEIGHT + 5))
INFO_X=$(( (TERM_WIDTH - 60) / 2 ))
INFO_X=$(( INFO_X < 2 ? 2 : INFO_X ))

tput cup $INFO_Y $INFO_X
printf "%b[ %bSYSTEM%b ] %b%s%b" "$C_COMMENT" "$C_REFINE" "$C_COMMENT" "$C_FG" "Initializing shell context..." "$C_RESET"
sleep 0.08

tput cup $((INFO_Y + 1)) $INFO_X
printf "%b[ %bTARGET%b ] %b%s%b" "$C_COMMENT" "$C_PLAN" "$C_COMMENT" "$C_FG" "Mounting workspace" "$C_RESET"
sleep 0.08

# Phase 4: Project details
DETAILS_Y=$((INFO_Y + 3))
DETAILS_X=$(( (TERM_WIDTH - 50) / 2 ))

tput cup $DETAILS_Y $DETAILS_X
printf "%bDIR: %b%s%b" "$C_COMMENT" "$C_FG" "$TARGET_DIR" "$C_RESET"

tput cup $((DETAILS_Y + 1)) $DETAILS_X
printf "%bPRJ: %b%s%b" "$C_COMMENT" "$C_PLAN" "$PROJECT_NAME" "$C_RESET"

tput cup $((DETAILS_Y + 2)) $DETAILS_X
if [ "$GIT_BRANCH" != "no-branch" ]; then
    printf "%bGIT: %b%s%b" "$C_COMMENT" "$C_BUILD" "$GIT_BRANCH" "$C_RESET"
else
    printf "%bGIT: %b(untracked)%b" "$C_COMMENT" "$C_COMMENT" "$C_RESET"
fi

sleep 0.2

# Phase 5: Launch
LAUNCH_TEXT="▸▸ LAUNCHING $PROJECT_NAME ◂◂"
LAUNCH_X=$(( (TERM_WIDTH - ${#LAUNCH_TEXT}) / 2 ))
tput cup $((DETAILS_Y + 5)) $LAUNCH_X
printf "%b%b%s%b%b" "$C_COMMENT" "$C_SCOUT" "$LAUNCH_TEXT" "$C_COMMENT" "$C_RESET"
sleep 0.25

# Cleanup
tput cnorm
clear
