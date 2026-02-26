#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <tag> <notes-file> [changelog-file]" >&2
    exit 1
fi

tag="$1"
notes_file="$2"
changelog_file="${3:-CHANGELOG.md}"
marker="<!-- OPENCHAD_RELEASE_NOTES -->"

if [ ! -f "$notes_file" ]; then
    echo "Notes file '${notes_file}' not found." >&2
    exit 1
fi

if [ -f "$changelog_file" ] && grep -Fq "## [${tag}]" "$changelog_file"; then
    echo "Changelog already contains ${tag}; skipping update."
    exit 0
fi

section_tmp=$(mktemp)
new_tmp=$(mktemp)

cleanup() {
    rm -f "$section_tmp" "$new_tmp"
}
trap cleanup EXIT

cat "$notes_file" > "$section_tmp"
printf '\n' >> "$section_tmp"

if [ ! -f "$changelog_file" ]; then
    {
        printf '# Changelog\n\n'
        printf 'All notable changes to this project are documented in this file.\n\n'
        printf '%s\n\n' "$marker"
        cat "$section_tmp"
    } > "$changelog_file"
    exit 0
fi

if ! grep -Fq "$marker" "$changelog_file"; then
    {
        printf '# Changelog\n\n'
        printf 'All notable changes to this project are documented in this file.\n\n'
        printf '%s\n\n' "$marker"
        cat "$section_tmp"
        cat "$changelog_file"
    } > "$new_tmp"
    mv "$new_tmp" "$changelog_file"
    exit 0
fi

awk -v marker="$marker" -v section_file="$section_tmp" '
{
    print
    if ($0 == marker) {
        print ""
        while ((getline line < section_file) > 0) {
            print line
        }
        close(section_file)
    }
}
' "$changelog_file" > "$new_tmp"

mv "$new_tmp" "$changelog_file"
