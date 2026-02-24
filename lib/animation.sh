#!/usr/bin/env bash
# open-chad: Boot animation (ayu-dark palette)
# Fast, contextual boot sequence
#
# Args: $1 = target directory

set -euo pipefail

TARGET_DIR="${1:-$PWD}"
PROJECT_NAME="$(basename "$TARGET_DIR")"
GIT_BRANCH="$(git -C "$TARGET_DIR" branch --show-current 2>/dev/null || echo "no-branch")"

# Handle interrupts gracefully
trap 'tput cnorm; clear; exit 0' INT TERM

# ayu-dark palette (true color)
C_STRING=$'\e[38;2;170;217;76m'      # #AAD94C green
C_ACCENT=$'\e[38;2;230;180;80m'      # #E6B450 golden yellow
C_TYPE=$'\e[38;2;89;194;255m'        # #59C2FF blue
C_KEYWORD=$'\e[38;2;255;143;64m'     # #FF8F40 orange
C_FUNC=$'\e[38;2;255;180;84m'        # #FFB454 functions orange
C_COMMENT=$'\e[38;2;98;109;122m'     # #626d7a gray
C_FG=$'\e[38;2;191;189;182m'         # #BFBDB6 foreground
C_RESET=$'\e[0m'

colors=("$C_STRING" "$C_ACCENT" "$C_TYPE" "$C_KEYWORD" "$C_FUNC" "$C_COMMENT")

logo=(
    "   ██████╗ ██████╗ ███████╗███╗   ██╗     ██████╗██╗  ██╗█████╗ ██████╗ "
    "  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║    ██╔════╝██║  ██║██╔══██╗██╔══██╗"
    "  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║    ██║     ███████║███████║██║  ██║"
    "  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║    ██║     ██╔══██║██╔══██║██║  ██║"
    "  ╚██████╔╝██║     ███████╗██║ ╚████║    ╚██████╗██║  ██║██║  ██║██████╔╝"
    "   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝     ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ "
)

# Hide cursor, clear screen
tput civis
clear

# Draw logo with static color mapping
tput cup 2 0
for i in "${!logo[@]}"; do
    color_idx=$((i % ${#colors[@]}))
    printf "%b%s%b\n" "${colors[$color_idx]}" "${logo[$i]}" "$C_RESET"
done

# Fast typewriter function
typewriter() {
    local text="$1"
    local color="$2"
    printf "%b" "$color"
    for (( i=0; i<${#text}; i++ )); do
        printf "%s" "${text:$i:1}"
        sleep 0.005 # Extremely fast
    done
    printf "%b\n" "$C_RESET"
}

# 1. Subtitle
tput cup 12 15
typewriter "O P E N - C H A D   1 . 0" "$C_TYPE"

sleep 0.1

# 2. Contextual Target Info
tput cup 14 10
printf "%b[ %bSYSTEM%b ] %b%s%b" "$C_COMMENT" "$C_STRING" "$C_COMMENT" "$C_FG" "Initializing shell context..." "$C_RESET"
sleep 0.1

tput cup 15 10
printf "%b[ %bTARGET%b ] %b%s%b" "$C_COMMENT" "$C_ACCENT" "$C_COMMENT" "$C_FG" "Mounting workspace" "$C_RESET"
sleep 0.1

tput cup 17 14
printf "%bDIR: %b%s%b" "$C_COMMENT" "$C_FG" "$TARGET_DIR" "$C_RESET"
tput cup 18 14
printf "%bPRJ: %b%s%b" "$C_COMMENT" "$C_ACCENT" "$PROJECT_NAME" "$C_RESET"
tput cup 19 14
if [ "$GIT_BRANCH" != "no-branch" ]; then
    printf "%bGIT: %b%s%b" "$C_COMMENT" "$C_TYPE" "$GIT_BRANCH" "$C_RESET"
else
    printf "%bGIT: %b(untracked)%b" "$C_COMMENT" "$C_COMMENT" "$C_RESET"
fi

sleep 0.2

# 3. Final launch (no progress bar, just go)
tput cup 22 22
printf "%b▸▸ %bLAUNCHING %s%b ◂◂%b" "$C_COMMENT" "$C_TYPE" "$PROJECT_NAME" "$C_COMMENT" "$C_RESET"
sleep 0.3

# Cleanup
tput cnorm
clear
