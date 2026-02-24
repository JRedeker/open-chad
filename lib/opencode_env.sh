#!/usr/bin/env bash
# lib/opencode_env.sh — Dedicated cache dir for open-chad
#
# Resolves OPEN_CHAD_CACHE_DIR using XDG Base Directory spec:
#   Primary:  $XDG_RUNTIME_DIR/open-chad   (Linux/systemd — auto-cleaned on logout)
#   Fallback: /tmp/open-chad-$USER          (macOS, containers, no systemd)
#
# Creates the directory with 0700 permissions (owner-only) and exports
# OPEN_CHAD_CACHE_DIR for use by all open-chad scripts.
#
# Usage (in other scripts):
#   source "$(dirname "${BASH_SOURCE[0]}")/opencode_env.sh"
#
# Override (for testing):
#   OPEN_CHAD_CACHE_DIR=/custom/path source lib/opencode_env.sh
#
# Safe to source multiple times (idempotent).

# Allow pre-existing override (e.g., for testing or custom installs)
if [ -z "${OPEN_CHAD_CACHE_DIR:-}" ]; then
    if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
        # XDG_RUNTIME_DIR is set — use it even if the parent doesn't exist yet;
        # mkdir -p below will create intermediate directories.
        OPEN_CHAD_CACHE_DIR="${XDG_RUNTIME_DIR}/open-chad"
    else
        # Fallback: user-private /tmp directory (macOS, containers without systemd)
        OPEN_CHAD_CACHE_DIR="/tmp/open-chad-${USER}"
    fi
fi

# Create directory with owner-only permissions (0700)
# mkdir -p is idempotent; chmod is a no-op when perms are already correct
mkdir -p "${OPEN_CHAD_CACHE_DIR}"
chmod 0700 "${OPEN_CHAD_CACHE_DIR}"

export OPEN_CHAD_CACHE_DIR
