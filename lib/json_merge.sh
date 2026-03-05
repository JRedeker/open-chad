#!/usr/bin/env bash
# lib/json_merge.sh — Idempotent additive JSON merge (Node.js, single code path)
#
# Usage: bash lib/json_merge.sh [--backup] [--rotate <N>] <target-file> <json-to-merge>
#
# Flags:
#   --backup          Create a timestamped .bak.<epoch> copy of <target-file>
#                     before merging. Backup is created with 0600 permissions.
#   --rotate <N>      After backup, keep only the N most-recent .bak.* files.
#                     N must be a positive integer (>= 1). Requires --backup.
#
# Behaviour:
#   - If <target-file> does not exist, creates it from <json-to-merge>
#   - Arrays: appended to existing, deduped (no clobber)
#   - Scalar keys: only added if not already present (no clobber)
#   - Nested objects: recursively merged with same rules
#   - Pretty-prints with 2-space indent + trailing newline
#   - Writes atomically: output goes to <target-file>.$$ then mv -f to final path
#
# Examples:
#   bash lib/json_merge.sh ~/.config/opencode/opencode.json \
#     '{"plugin":["/path/to/adv/plugin"]}'
#
#   bash lib/json_merge.sh --backup --rotate 5 \
#     ~/.config/opencode/opencode.json \
#     '{"instructions":["~/.config/opencode/shell_strategy.md"]}'

set -euo pipefail

# ─── Flag parsing ─────────────────────────────────────────────────────────────

_BACKUP=0
_ROTATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup)
            _BACKUP=1
            shift
            ;;
        --rotate)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: json_merge.sh: --rotate requires a positive integer argument." >&2
                exit 1
            fi
            _ROTATE="$2"
            # Validate: must be a positive integer
            if ! [[ "$_ROTATE" =~ ^[0-9]+$ ]] || [ "$_ROTATE" -lt 1 ]; then
                echo "ERROR: json_merge.sh: --rotate value must be a positive integer (>= 1), got: '$_ROTATE'" >&2
                exit 1
            fi
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "ERROR: json_merge.sh: unknown flag: $1" >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

TARGET_FILE="${1:?Usage: json_merge.sh [--backup] [--rotate N] <target-file> <json-to-merge>}"
MERGE_JSON="${2:?Usage: json_merge.sh [--backup] [--rotate N] <target-file> <json-to-merge>}"

if ! command -v node &>/dev/null; then
    echo "ERROR: node is required for json_merge.sh but was not found in PATH." >&2
    echo "       Install Node.js: https://nodejs.org/" >&2
    exit 1
fi

# 1MB size guard — reject oversized inputs before Node.js parse to prevent
# runaway memory use or accidental config corruption from huge payloads.
_MAX_SIZE=1048576

if [ -f "$TARGET_FILE" ]; then
    _target_size=$(wc -c < "$TARGET_FILE" 2>/dev/null || echo 0)
    if [ "$_target_size" -gt "$_MAX_SIZE" ]; then
        echo "ERROR: json_merge.sh: target file is too large (${_target_size} bytes > 1MB limit): $TARGET_FILE" >&2
        echo "       Refusing to parse. Check for accidental config file corruption." >&2
        exit 1
    fi
fi

_payload_size=${#MERGE_JSON}
if [ "$_payload_size" -gt "$_MAX_SIZE" ]; then
    echo "ERROR: json_merge.sh: merge payload is too large (${_payload_size} bytes > 1MB limit)." >&2
    echo "       Refusing to parse. Reduce the size of the JSON being merged." >&2
    exit 1
fi

# ─── Backup (opt-in via --backup) ────────────────────────────────────────────

if [ "$_BACKUP" -eq 1 ] && [ -f "$TARGET_FILE" ]; then
    _bak_file="${TARGET_FILE}.bak.$(date +%s)"
    # Create backup with 0600 permissions atomically
    install -m 0600 "$TARGET_FILE" "$_bak_file" 2>/dev/null || {
        cp "$TARGET_FILE" "$_bak_file"
        chmod 0600 "$_bak_file" 2>/dev/null || true
    }

    # Rotate: keep only the N most-recent backups
    if [ -n "$_ROTATE" ]; then
        # List backups newest-first, skip the first N, delete the rest
        # Use ls -t for time-sorted listing (newest first)
        ls -t "${TARGET_FILE}".bak.* 2>/dev/null \
            | tail -n +"$((_ROTATE + 1))" \
            | xargs -r rm -f --
    fi
fi

# ─── Atomic temp file setup ───────────────────────────────────────────────────
# Write merged output to a PID-suffixed temp file in the same directory as the
# target, then atomically rename. Same-filesystem guarantee ensures mv is atomic.

_TMP_FILE="${TARGET_FILE}.$$"

# Ensure temp file is cleaned up on any error exit
trap 'rm -f "$_TMP_FILE"' EXIT

node - "$TARGET_FILE" "$MERGE_JSON" "$_TMP_FILE" <<'EOF'
const fs   = require('fs');
const path = require('path');

const targetPath = process.argv[2];
const mergeJson  = process.argv[3];
const tmpPath    = process.argv[4];

// Parse the incoming merge payload
let toAdd;
try {
    toAdd = JSON.parse(mergeJson);
} catch (e) {
    console.error('ERROR: json_merge.sh received invalid JSON:', mergeJson);
    process.exit(1);
}

// Load existing or start empty
let existing = {};
if (fs.existsSync(targetPath)) {
    try {
        existing = JSON.parse(fs.readFileSync(targetPath, 'utf8'));
    } catch (e) {
        console.error('ERROR: json_merge.sh could not parse existing file:', targetPath);
        console.error(e.message);
        process.exit(1);
    }
}

/**
 * Idempotent additive merge:
 *   - Arrays: append items not already present (dedup by string equality)
 *   - Objects: recurse
 *   - Scalars: only set if key not already in target
 */
function merge(target, source) {
    const result = JSON.parse(JSON.stringify(target)); // deep clone
    for (const key of Object.keys(source)) {
        if (Array.isArray(source[key])) {
            result[key] = result[key] || [];
            const existing_set = new Set(result[key].map(v => JSON.stringify(v)));
            for (const item of source[key]) {
                const serialized = JSON.stringify(item);
                if (!existing_set.has(serialized)) {
                    result[key].push(item);
                    existing_set.add(serialized);
                }
            }
        } else if (
            source[key] !== null &&
            typeof source[key] === 'object' &&
            !Array.isArray(source[key])
        ) {
            result[key] = merge(result[key] || {}, source[key]);
        } else {
            // Scalar: only add if key not present
            if (!(key in result)) {
                result[key] = source[key];
            }
        }
    }
    return result;
}

const merged = merge(existing, toAdd);

// Ensure parent directory exists
const dir = path.dirname(targetPath);
if (dir && !fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
}

// Write to temp file first, then atomically rename (POSIX rename(2) guarantee)
fs.writeFileSync(tmpPath, JSON.stringify(merged, null, 2) + '\n', 'utf8');
fs.renameSync(tmpPath, targetPath);
EOF

# Clear the EXIT trap — Node.js already renamed the temp file to the target.
# If renameSync succeeded, _TMP_FILE no longer exists; trap is a no-op either way.
trap - EXIT
