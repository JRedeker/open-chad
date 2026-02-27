#!/usr/bin/env bash
# lib/status_edges.sh — per-session synthwave edge renderer for tmux status bars
#
# Each of the 4 edge positions (left-row0, right-row0, left-row1, right-row1)
# picks its own variant independently, giving 4^4 = 256 possible combinations.
# Color order is always fixed: build -> plan -> scout -> refine

set -euo pipefail

side="${1:-left}"   # left | right
row="${2:-row0}"    # row0 | row1
session_name="${3:-default}"

# Keep color order fixed as a mnemonic:
# build (blue) -> plan (yellow) -> scout (pink) -> refine (green)
c1="#59C2FF"
c2="#FFB454"
c3="#F07178"
c4="#AAD94C"

# Derive a numeric seed from a string (djb2-inspired hash)
_hash_string() {
    local input="$1"
    local i ch ord seed=5381

    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        printf -v ord '%d' "'${ch}"
        seed=$(( (seed * 33 + ord) % 2147483647 ))
    done

    printf '%s' "$seed"
}

# Compute variant for this specific position (0-3)
# Each position gets an independent variant derived from session + position salt
_position_variant() {
    local position_key="${session_name}:${side}:${row}"
    local seed
    seed=$(_hash_string "$position_key")
    printf '%s' "$(( seed % 4 ))"
}

_pick_glyphs() {
    local variant="$1"

    # Default patterns (index 0)
    g1='█'; g2='▌'; g3='▌'; g4='▌'

    case "${side}:${row}:${variant}" in
        left:row0:0) g1='█'; g2='▌'; g3='▌'; g4='▌' ;;
        left:row0:1) g1='▛'; g2='▌'; g3='▌'; g4='▌' ;;
        left:row0:2) g1='▜'; g2='▌'; g3='▌'; g4='▌' ;;
        left:row0:3) g1='▙'; g2='▌'; g3='▌'; g4='▌' ;;

        right:row0:0) g1='▐'; g2='▐'; g3='▐'; g4='█' ;;
        right:row0:1) g1='▐'; g2='▐'; g3='▐'; g4='▟' ;;
        right:row0:2) g1='▐'; g2='▐'; g3='▐'; g4='▙' ;;
        right:row0:3) g1='▐'; g2='▐'; g3='▐'; g4='▜' ;;

        left:row1:0) g1='█'; g2='▌'; g3='▌'; g4='▌' ;;
        left:row1:1) g1='▛'; g2='█'; g3='▌'; g4='▌' ;;
        left:row1:2) g1='▜'; g2='█'; g3='▌'; g4='▌' ;;
        left:row1:3) g1='▙'; g2='█'; g3='▌'; g4='▌' ;;

        right:row1:0) g1='▐'; g2='▐'; g3='▐'; g4='█' ;;
        right:row1:1) g1='▐'; g2='▐'; g3='█'; g4='▟' ;;
        right:row1:2) g1='▐'; g2='▐'; g3='█'; g4='▙' ;;
        right:row1:3) g1='▐'; g2='▐'; g3='█'; g4='▜' ;;
    esac
}

variant=$(_position_variant)
_pick_glyphs "$variant"

printf '#[fg=%s]%s#[fg=%s]%s#[fg=%s]%s#[fg=%s]%s' \
    "$c1" "$g1" "$c2" "$g2" "$c3" "$g3" "$c4" "$g4"
