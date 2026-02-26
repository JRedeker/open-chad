#!/usr/bin/env bash
# completion/openchad.bash — bash completion for openchad and oc
#
# Source this file or add to /etc/bash_completion.d/ or ~/.bash_completion:
#   source /path/to/open-chad/completion/openchad.bash
#
# setup_shell_profile.sh wires this automatically.

# _openchad_project_names — emit de-duped project names from ~/dev
# Includes top-level dirs and one-level-deep dirs. Nested names that
# collide with a top-level name are suppressed to avoid misleading
# suggestions (top-level always wins in resolution).
_openchad_project_names() {
    local dev_dir="${HOME}/dev"
    [ -d "$dev_dir" ] || return 0

    declare -A _seen=()
    local name d

    # Top-level dirs
    for d in "${dev_dir}"/*/; do
        [ -d "$d" ] || continue
        name="${d%/}"
        name="${name##*/}"
        _seen["$name"]=1
        printf '%s\n' "$name"
    done

    # One-level nested dirs — only emit if name not already seen at top level
    for d in "${dev_dir}"/*/*/; do
        [ -d "$d" ] || continue
        name="${d%/}"
        name="${name##*/}"
        [ "${_seen[$name]+set}" = "set" ] && continue
        _seen["$name"]=1
        printf '%s\n' "$name"
    done
}

_openchad_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    }

    local subcommands="update version doctor uninstall metrics changelog discord"
    local options="--no-anim --help -h"

    # Top-level subcommand/project completion
    if [ "$COMP_CWORD" -eq 1 ]; then
        local project_names
        project_names=$(_openchad_project_names 2>/dev/null || true)
        COMPREPLY=( $(compgen -W "$subcommands $options $project_names" -- "$cur") )
        return 0
    fi

    # Sub-subcommand completion
    case "${COMP_WORDS[1]}" in
        metrics)
            COMPREPLY=( $(compgen -W "log export show" -- "$cur") )
            ;;
        changelog)
            COMPREPLY=( $(compgen -W "latest" -- "$cur") )
            ;;
        discord)
            COMPREPLY=( $(compgen -W "enable disable status" -- "$cur") )
            ;;
        *)
            # Default: complete with directories for project-dir arg
            COMPREPLY=( $(compgen -d -- "$cur") )
            ;;
    esac
    return 0
}

complete -F _openchad_completions openchad
complete -F _openchad_completions oc
