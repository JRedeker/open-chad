#compdef openchad oc
# completion/_openchad.zsh — zsh completion for openchad and oc
#
# Install by adding the completion directory to fpath:
#   fpath=(/path/to/open-chad/completion $fpath)
#   autoload -Uz compinit && compinit
#
# setup_shell_profile.sh wires this automatically.

# _openchad_project_names — emit de-duped project names from ~/dev
# Includes top-level dirs and one-level-deep dirs. Nested names that
# collide with a top-level name are suppressed (top-level always wins
# in resolution, so offering both would be misleading).
_openchad_project_names() {
    local dev_dir="${HOME}/dev"
    [[ -d "$dev_dir" ]] || return 0

    local -A _seen=()
    local name d

    # Top-level dirs
    for d in "${dev_dir}"/*/; do
        [[ -d "$d" ]] || continue
        name="${d%/}"
        name="${name##*/}"
        _seen[$name]=1
        print -- "$name"
    done

    # One-level nested dirs — only emit if name not already seen at top level
    for d in "${dev_dir}"/*/*/; do
        [[ -d "$d" ]] || continue
        name="${d%/}"
        name="${name##*/}"
        (( ${+_seen[$name]} )) && continue
        _seen[$name]=1
        print -- "$name"
    done
}

_openchad() {
    local state

    _arguments \
        '(-h --help)'{-h,--help}'[Show help]' \
        '--no-anim[Skip boot animation]' \
        '1: :->subcommand' \
        '*: :->args'

    case "$state" in
        subcommand)
            local subcommands=(
                'update:Pull latest openchad changes and re-run setup'
                'version:Show openchad version'
                'doctor:Validate install health (symlinks, theme, plugins, cache)'
                'uninstall:Remove openchad symlinks and shell profile blocks'
                'metrics:Show or log system metrics'
                'changelog:Show git log since last tag'
                'discord:Manage Discord Rich Presence'
            )
            # Also offer project names from ~/dev with a description
            local project_names=()
            local pname
            while IFS= read -r pname; do
                [[ -n "$pname" ]] && project_names+=("${pname}:Project in ~/dev")
            done < <(_openchad_project_names 2>/dev/null)

            _describe 'subcommand' subcommands
            (( ${#project_names[@]} > 0 )) && _describe 'project' project_names
            ;;
        args)
            case "${words[2]}" in
                metrics)
                    local metrics_cmds=(
                        'log:Append timestamped reading to history'
                        'export:Print current metrics as JSON'
                        'show:Print current metrics (default)'
                    )
                    _describe 'metrics subcommand' metrics_cmds
                    ;;
                changelog)
                    local changelog_cmds=(
                        'latest:Show last tag release notes'
                    )
                    _describe 'changelog subcommand' changelog_cmds
                    ;;
                discord)
                    local discord_cmds=(
                        'enable:Enable Discord Rich Presence'
                        'disable:Disable Discord Rich Presence'
                        'status:Show Discord Rich Presence status'
                    )
                    _describe 'discord subcommand' discord_cmds
                    ;;
                *)
                    _files -/
                    ;;
            esac
            ;;
    esac
}

_openchad "$@"
