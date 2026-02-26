#!/usr/bin/env bash
# completion/openchad.bash — bash completion for openchad and oc
#
# Source this file or add to /etc/bash_completion.d/ or ~/.bash_completion:
#   source /path/to/open-chad/completion/openchad.bash
#
# setup_shell_profile.sh wires this automatically.

_openchad_completions() {
    local cur prev words cword
    _init_completion 2>/dev/null || {
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    }

    local subcommands="update version doctor uninstall metrics changelog discord"
    local options="--no-anim --help -h"

    # Top-level subcommand completion
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$subcommands $options" -- "$cur") )
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
