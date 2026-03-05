# Shell Non-Interactive Strategy

This environment has **no TTY/PTY**. Any command that waits for input, opens an editor, or launches a pager will hang and timeout. Treat all shell execution as headless CI.

**Precedence:** When these rules conflict with `rules.yaml`, follow priority-based resolution. Notably, P01 (security/least-privilege) overrides force flags for destructive operations — confirm before `rm -rf`, `drop`, etc.

## Core Rules

1. Never launch editors, pagers, or bare REPLs — they hang forever.
2. Always supply non-interactive flags (`-y`, `--yes`, `--no-edit`, `--non-interactive`) when available.
3. Use `Read`/`Write`/`Edit` tools for file operations instead of `sed`/`awk`/`cat`/`echo`.
4. Wrap risky commands with `timeout` if no non-interactive flag exists.

## Banned Commands (Will Hang)

Editors: `vim`, `vi`, `nano`, `emacs`, `pico`, `ed`
Pagers: `less`, `more`, `most`, `man`
Interactive git: `git add -p`, `git rebase -i`, `git commit` (without `-m`)
Bare REPLs: `python`, `node`, `irb`, `ghci` (without script/command)
Interactive shells: `bash -i`, `zsh -i`

## Environment Variables

These prevent interactive prompts and should be set in the shell environment:

| Variable | Value | Purpose |
|----------|-------|---------|
| `CI` | `true` | General CI detection |
| `DEBIAN_FRONTEND` | `noninteractive` | Apt/dpkg prompts |
| `GIT_TERMINAL_PROMPT` | `0` | Git auth prompts |
| `GIT_EDITOR` | `true` | Block git editor |
| `GIT_PAGER` | `cat` | Disable git pager |
| `PAGER` | `cat` | Disable system pager |
| `npm_config_yes` | `true` | NPM prompts |
| `PIP_NO_INPUT` | `1` | Pip prompts |

## Git (High-Frequency)

| BAD | GOOD |
|-----|------|
| `git commit` | `git commit -m "msg"` |
| `git merge branch` | `git merge --no-edit branch` |
| `git pull` | `git pull --no-edit` |
| `git rebase -i` | `git rebase` (non-interactive) |
| `git add -p` | `git add .` or `git add <file>` |
| `git log` | `git --no-pager log` or `git log -n 10` |
| `git diff` | `git --no-pager diff` |

## Package Managers & System

| BAD | GOOD |
|-----|------|
| `npm init` | `npm init -y` |
| `apt-get install pkg` | `apt-get install -y pkg` |
| `pip install pkg` | `pip install --no-input pkg` |
| `ssh host` | `ssh -o BatchMode=yes -o StrictHostKeyChecking=no host` |

## Sub-Agent Restrictions

**No Shell Access:** The `explore` and `librarian` sub-agents have `bash: false` in their tool permissions. They cannot execute shell commands at all — read-only or otherwise. This is enforced at the capability level, not by convention.

These agents use `read`, `glob`, `grep`, and `lgrep_search_semantic` for codebase exploration. If you need to run shell commands (even read-only ones like `git log` or `rg`), use a primary agent (`general` or `build`) instead.

## Fallback Patterns

When no non-interactive flag exists:

```bash
# Pipe yes to scripts that prompt
yes | ./install_script.sh

# Heredoc for multi-prompt scripts
./configure.sh <<EOF
option1
option2
EOF

# Timeout wrapper (last resort)
timeout 30 ./potentially_hanging_script.sh || echo "Timed out"
```
