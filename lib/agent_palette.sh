#!/usr/bin/env bash
# lib/agent_palette.sh — canonical primary agent color constants

# Primary agent palette (official, do not drift)
OPEN_CHAD_COLOR_BUILD="#59C2FF"
OPEN_CHAD_COLOR_PLAN="#FFB454"
OPEN_CHAD_COLOR_SCOUT="#F07178"
OPEN_CHAD_COLOR_REFINE="#AAD94C"

# True-color ANSI equivalents
OPEN_CHAD_ANSI_BUILD=$'\e[38;2;89;194;255m'
OPEN_CHAD_ANSI_PLAN=$'\e[38;2;255;180;84m'
OPEN_CHAD_ANSI_SCOUT=$'\e[38;2;240;113;120m'
OPEN_CHAD_ANSI_REFINE=$'\e[38;2;170;217;76m'

open_chad_agent_color() {
    case "${1:-}" in
        build) printf '%s' "$OPEN_CHAD_COLOR_BUILD" ;;
        plan) printf '%s' "$OPEN_CHAD_COLOR_PLAN" ;;
        scout) printf '%s' "$OPEN_CHAD_COLOR_SCOUT" ;;
        refine) printf '%s' "$OPEN_CHAD_COLOR_REFINE" ;;
        *) printf '%s' '' ;;
    esac
}
