#!/usr/bin/env bash
# lib/openchad_version.sh — openchad version subcommand handler
#
# Prints the current openchad version from git tag or hardcoded constant.
# Called by: bin/openchad version

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Hardcoded fallback version (updated on release)
OPENCHAD_VERSION_FALLBACK="1.2.0"

# Try to get version from git tag
_version=""
if command -v git >/dev/null 2>&1 && [ -d "$REPO_DIR/.git" ]; then
    _version=$(git -C "$REPO_DIR" describe --tags --exact-match 2>/dev/null || true)
    if [ -z "$_version" ]; then
        # Not on a tag — show nearest tag + commit distance
        _version=$(git -C "$REPO_DIR" describe --tags --always 2>/dev/null || true)
    fi
fi

# Fall back to hardcoded constant if git unavailable or no tags
if [ -z "$_version" ]; then
    _version="$OPENCHAD_VERSION_FALLBACK"
fi

echo "openchad $_version"
