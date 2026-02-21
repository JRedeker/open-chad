#!/usr/bin/env bash
# open-chad: Boot animation (Muted Apple/Amiga 80s palette)
# Fast, contextual boot sequence
#
# Args: $1 = target directory

set -euo pipefail

TARGET_DIR="${1:-$PWD}"
PROJECT_NAME="$(basename "$TARGET_DIR")"
GIT_BRANCH="$(git -C "$TARGET_DIR" branch --show-current 2>/dev/null || echo "no-branch")"

# Handle interrupts gracefully
trap 'tput cnorm; clear; exit 0' INT TERM

# Muted palette ANSI codes
C_SAGE="\e[38;5;107m"
C_GOLD="\e[38;5;186m"
C_CORAL="\e[38;5;173m"
C_BRICK="\e[38;5;131m"
C_LAVENDER="\e[38;5;139m"
C_STEEL="\e[38;5;67m"
C_WHITE="\e[38;5;188m"
C_DIM="\e[38;5;242m"
C_RESET="\e[0m"

colors=("$C_SAGE" "$C_GOLD" "$C_CORAL" "$C_BRICK" "$C_LAVENDER" "$C_STEEL")

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
typewriter "O P E N - C H A D   1 . 0" "$C_STEEL"

sleep 0.1

# 2. Contextual Target Info
tput cup 14 10
printf "%b[ %bSYSTEM%b ] %b%s%b" "$C_DIM" "$C_SAGE" "$C_DIM" "$C_WHITE" "Initializing shell context..." "$C_RESET"
sleep 0.1

tput cup 15 10
printf "%b[ %bTARGET%b ] %b%s%b" "$C_DIM" "$C_GOLD" "$C_DIM" "$C_WHITE" "Mounting workspace" "$C_RESET"
sleep 0.1

tput cup 17 14
printf "%bDIR: %b%s%b" "$C_DIM" "$C_WHITE" "$TARGET_DIR" "$C_RESET"
tput cup 18 14
printf "%bPRJ: %b%s%b" "$C_DIM" "$C_GOLD" "$PROJECT_NAME" "$C_RESET"
tput cup 19 14
if [ "$GIT_BRANCH" != "no-branch" ]; then
    printf "%bGIT: %b%s%b" "$C_DIM" "$C_CORAL" "$GIT_BRANCH" "$C_RESET"
else
    printf "%bGIT: %b(untracked)%b" "$C_DIM" "$C_DIM" "$C_RESET"
fi

sleep 0.2

# 3. Final launch (no progress bar, just go)
tput cup 22 22
printf "%b▸▸ %bLAUNCHING %s%b ◂◂%b" "$C_DIM" "$C_STEEL" "$PROJECT_NAME" "$C_DIM" "$C_RESET"
sleep 0.3

# Cleanup
tput cnorm
clear
