#!/usr/bin/env bash
# lib/openchad_changelog.sh — openchad changelog subcommand handler
#
# Subcommands:
#   openchad changelog         — print git log --oneline since last tag
#   openchad changelog latest  — show last tag name and its annotated notes
#
# Called by: bin/openchad changelog [latest]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

_subcommand="${1:-}"
shift || true

if ! command -v git >/dev/null 2>&1 || [ ! -d "$REPO_DIR/.git" ]; then
    echo "openchad changelog: git not available or not a git repo" >&2
    exit 1
fi

_last_tag=$(git -C "$REPO_DIR" describe --tags --abbrev=0 2>/dev/null || true)

case "$_subcommand" in
    latest)
        if [ -z "$_last_tag" ]; then
            echo "No tags found in this repository."
            exit 0
        fi
        echo "Latest release: $_last_tag"
        echo ""
        # Show annotated tag message if available, else show the commit
        _tag_msg=$(git -C "$REPO_DIR" tag -l --format='%(contents)' "$_last_tag" 2>/dev/null || true)
        if [ -n "$_tag_msg" ]; then
            echo "$_tag_msg"
        else
            git -C "$REPO_DIR" --no-pager log -1 --format="%s%n%n%b" "$_last_tag" 2>/dev/null || true
        fi
        ;;
    "")
        # Default: show commits since last tag
        if [ -z "$_last_tag" ]; then
            echo "No tags found — showing last 20 commits:"
            git -C "$REPO_DIR" --no-pager log --oneline -20 2>/dev/null || true
        else
            _count=$(git -C "$REPO_DIR" rev-list "${_last_tag}..HEAD" --count 2>/dev/null || echo 0)
            if [ "$_count" -eq 0 ]; then
                echo "No changes since $_last_tag."
            else
                echo "Changes since $_last_tag ($_count commit(s)):"
                echo ""
                git -C "$REPO_DIR" --no-pager log --oneline "${_last_tag}..HEAD" 2>/dev/null || true
            fi
        fi
        ;;
    *)
        echo "Usage: openchad changelog [latest]" >&2
        exit 1
        ;;
esac
