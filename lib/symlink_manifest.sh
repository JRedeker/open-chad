#!/usr/bin/env bash
# lib/symlink_manifest.sh — Single source of truth for managed ~/.local/bin symlinks
#
# Source this file to get MANAGED_SYMLINKS as an associative array:
#   key   = symlink name in ~/.local/bin
#   value = relative path from repo root to the target binary
#
# Used by: install.sh, lib/update.sh, lib/openchad_doctor.sh,
#          lib/openchad_uninstall.sh, and installer tests.
#
# Adding a new command? Add it here ONLY — all consumers pick it up automatically.

# Associative array: symlink_name -> repo-relative binary path
declare -A MANAGED_SYMLINKS=(
    ["openchad"]="bin/openchad"
    ["oc"]="bin/oc"
    ["cds"]="bin/cds"
    ["oc-list"]="bin/oc-list"
    ["oc-killall"]="bin/oc-killall"
)
