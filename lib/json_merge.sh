#!/usr/bin/env bash
# lib/json_merge.sh — Idempotent additive JSON merge (Node.js, single code path)
#
# Usage: bash lib/json_merge.sh <target-file> <json-to-merge>
#
# Behaviour:
#   - If <target-file> does not exist, creates it from <json-to-merge>
#   - Arrays: appended to existing, deduped (no clobber)
#   - Scalar keys: only added if not already present (no clobber)
#   - Nested objects: recursively merged with same rules
#   - Pretty-prints with 2-space indent + trailing newline
#
# Examples:
#   bash lib/json_merge.sh ~/.config/opencode/opencode.json \
#     '{"plugin":["/path/to/adv/plugin"]}'
#
#   bash lib/json_merge.sh ~/.config/opencode/opencode.json \
#     '{"instructions":["~/.config/opencode/shell_strategy.md"]}'

set -euo pipefail

TARGET_FILE="${1:?Usage: json_merge.sh <target-file> <json-to-merge>}"
MERGE_JSON="${2:?Usage: json_merge.sh <target-file> <json-to-merge>}"

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

node - "$TARGET_FILE" "$MERGE_JSON" <<'EOF'
const fs   = require('fs');
const path = require('path');

const targetPath = process.argv[2];
const mergeJson  = process.argv[3];

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

fs.writeFileSync(targetPath, JSON.stringify(merged, null, 2) + '\n', 'utf8');
EOF
