#compdef openchad oc
# completion/_openchad.zsh — zsh completion for openchad and oc
#
# Install by adding the completion directory to fpath:
#   fpath=(/path/to/open-chad/completion $fpath)
#   autoload -Uz compinit && compinit
#
# setup_shell_profile.sh wires this automatically.

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
            _describe 'subcommand' subcommands
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
