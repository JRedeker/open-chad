#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <tag> <output-file>" >&2
    exit 1
fi

tag="$1"
output_file="$2"

if ! git rev-parse --verify "${tag}^{commit}" >/dev/null 2>&1; then
    echo "Tag '${tag}' does not resolve to a commit." >&2
    exit 1
fi

previous_tag=$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)
if [ -n "$previous_tag" ]; then
    range="${previous_tag}..${tag}"
else
    range="$tag"
fi

declare -a features fixes docs tests chores others

while IFS='|' read -r subject sha; do
    [ -n "$subject" ] || continue
    short_sha="${sha:0:7}"

    case "$subject" in
        feat:*) features+=("- ${subject#feat: } (${short_sha})") ;;
        fix:*) fixes+=("- ${subject#fix: } (${short_sha})") ;;
        docs:*) docs+=("- ${subject#docs: } (${short_sha})") ;;
        test:*|tests:*) tests+=("- ${subject#*: } (${short_sha})") ;;
        chore:*|ci:*|build:*) chores+=("- ${subject#*: } (${short_sha})") ;;
        *) others+=("- ${subject} (${short_sha})") ;;
    esac
done < <(git log --pretty=format:'%s|%H' "$range")

emit_section() {
    local title="$1"
    shift

    if [ "$#" -eq 0 ]; then
        return
    fi

    printf '### %s\n\n' "$title" >> "$output_file"
    printf '%s\n' "$@" >> "$output_file"
    printf '\n' >> "$output_file"
}

date_utc=$(date -u +"%Y-%m-%d")

{
    printf '## [%s] - %s\n\n' "$tag" "$date_utc"
} > "$output_file"

emit_section "Features" "${features[@]}"
emit_section "Fixes" "${fixes[@]}"
emit_section "Documentation" "${docs[@]}"
emit_section "Tests" "${tests[@]}"
emit_section "Maintenance" "${chores[@]}"
emit_section "Other" "${others[@]}"

if [ ! -s "$output_file" ] || [ "$(wc -l < "$output_file")" -lt 3 ]; then
    {
        printf '## [%s] - %s\n\n' "$tag" "$date_utc"
        printf -- '- No user-facing changes in this release.\n'
    } > "$output_file"
fi
