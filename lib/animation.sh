#!/usr/bin/env bash
# open-chad: Boot animation (stroke palette)
# Centered, color-cycling boot sequence with outline-style logo
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
C_DIM=$'\e[38;2;60;68;81m'           # #3C4451 dim gray
C_RESET=$'\e[0m'

colors=("$C_BUILD" "$C_PLAN" "$C_SCOUT" "$C_REFINE")

# ═══════════════════════════════════════════════════════════════════════════════
# OPEN CHAD LOGO (74 chars wide, 6 lines — outline/stroke style)
# ═══════════════════════════════════════════════════════════════════════════════

logo=(
    "   ┌─────┐ ┌─────┐ ┌──────┐┌──┐  ┌──┐    ┌─────┐┌──┐ ┌──┐┌────┐ ┌─────┐"
    "   │ ┌─┐ │ │ ┌─┐ │ │ ┌────┘│  └┐ │  │    │ ┌───┘│  │ │  ││ ┌┐ │ │ ┌─┐ │"
    "   │ │ │ │ │ └─┘ │ │ └──┐  │ ┌┐└┐│  │    │ │    │ └─┘ ││ └┘ │ │ │ │ │ │"
    "   │ │ │ │ │ ┌───┘ │ ┌──┘  │ │└┐└┘  │    │ │    │ ┌─┐ ││ ┌┐ │ │ │ │ │ │"
    "   │ └─┘ │ │ │     │ └────┐│ │ └┐   │    │ └───┐│ │ │ ││ │└─┘ │ │ └─┘ │"
    "   └─────┘ └─┘     └──────┘└─┘  └───┘    └─────┘└─┘ └─┘└─┘    └─┘     └─┘"
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
# Each line gets one accent color from the palette as a stroke tint;
# the rest of the animation stays in gray/foreground tones.
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

# Phase 1: Color cycling animation (primary palette as stroke tint)
for cycle in {0..3}; do
    draw_logo "$cycle"
    sleep 0.15
done

# Settle on dim gray — the accent colors were just a flash
for i in "${!logo[@]}"; do
    tput cup $((LOGO_Y + i)) $LOGO_X
    printf "%b%s%b" "$C_DIM" "${logo[$i]}" "$C_RESET"
done

sleep 0.08

# Phase 2: Subtitle (centered, muted)
SUBTITLE="O P E N C H A D   1 . 3"
SUBTITLE_X=$(( (TERM_WIDTH - ${#SUBTITLE}) / 2 ))
tput cup $((LOGO_Y + LOGO_HEIGHT + 2)) $SUBTITLE_X
typewriter "$SUBTITLE" "$C_COMMENT"

sleep 0.1

# Phase 3: Context info (centered, gray labels)
INFO_Y=$((LOGO_Y + LOGO_HEIGHT + 5))
INFO_X=$(( (TERM_WIDTH - 60) / 2 ))
INFO_X=$(( INFO_X < 2 ? 2 : INFO_X ))

tput cup $INFO_Y $INFO_X
printf "%b· %bsystem%b  %b%s%b" "$C_DIM" "$C_COMMENT" "$C_DIM" "$C_FG" "initializing context" "$C_RESET"
sleep 0.08

tput cup $((INFO_Y + 1)) $INFO_X
printf "%b· %btarget%b  %b%s%b" "$C_DIM" "$C_COMMENT" "$C_DIM" "$C_FG" "mounting workspace" "$C_RESET"
sleep 0.08

# Phase 4: Project details (minimal, gray)
DETAILS_Y=$((INFO_Y + 3))
DETAILS_X=$(( (TERM_WIDTH - 50) / 2 ))

tput cup $DETAILS_Y $DETAILS_X
printf "%bdir  %b%s%b" "$C_DIM" "$C_FG" "$TARGET_DIR" "$C_RESET"

tput cup $((DETAILS_Y + 1)) $DETAILS_X
printf "%bprj  %b%s%b" "$C_DIM" "$C_FG" "$PROJECT_NAME" "$C_RESET"

tput cup $((DETAILS_Y + 2)) $DETAILS_X
if [ "$GIT_BRANCH" != "no-branch" ]; then
    printf "%bgit  %b%s%b" "$C_DIM" "$C_COMMENT" "$GIT_BRANCH" "$C_RESET"
else
    printf "%bgit  %b(untracked)%b" "$C_DIM" "$C_DIM" "$C_RESET"
fi

sleep 0.2

# Phase 5: Launch (single accent flash)
LAUNCH_TEXT="▸ launching $PROJECT_NAME"
LAUNCH_X=$(( (TERM_WIDTH - ${#LAUNCH_TEXT}) / 2 ))
tput cup $((DETAILS_Y + 5)) $LAUNCH_X
printf "%b%s%b" "$C_COMMENT" "$LAUNCH_TEXT" "$C_RESET"
sleep 0.25

# Cleanup
tput cnorm
clear
