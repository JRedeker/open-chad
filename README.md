# open-chad

A retro tmux launcher and orchestrator for [OpenCode](https://github.com/opencode-ai/opencode).

Designed for developers who run 5-10+ concurrent OpenCode sessions and need instant visual context when switching tabs.

Inspired by [NvChad](https://github.com/NvChad/NvChad) and its focus on a fast, beautiful developer experience. Color theme by [opencode-ayu-theme](https://github.com/postrednik/opencode-ayu-theme), based on [ayu](https://github.com/ayu-theme/ayu).

## Features

- **Boot Animation**: ayu-dark color-cycling logo and contextual launch sequence (skippable via `--no-anim`).
- **Unified ayu-dark Monitor**: Transforms tmux into a 2-row display using the ayu-dark palette (green, gold, blue, orange).
- **Smart Context Bar**: 
  - Left: repo name + branch.
  - Row 2 left: LLM fuel gauge + ADV window title parser (extracts `EMOJI REPO CHANGE_ID` into structured zones).
  - Row 2 right: live CPU%, RAM%, and load average.
- **LLM Fuel Gauge**: Displays per-provider quota remaining as `Z.ai 62% | Copilot 81% | Claude 47% | Codex 94%` in the tmux status bar. Each provider segment is color-coded: green ≥50%, yellow 20–49%, red <20%. Unknown or failed providers show `--` in gray. Updated live every 30s via background collector.
- **Shared System Metrics**: Background singleton collector tracks CPU%, RAM%, Load Avg, and LLM fuel across all sessions with near-zero overhead.
- **Crash Isolation**: Wraps every OpenCode instance in an isolated tmux session (`oc-<timestamp>-<pid>`) to prevent WSL/terminal cascade failures.

## Installation

```bash
cd ~/dev
git clone https://github.com/JRedeker/open-chad.git
cd open-chad
./install.sh
```

This will:
1. Symlink `bin/open-chad` to `~/.local/bin/`.
2. Update your `~/.tmux.conf` to source the ayu-dark tmux theme.
3. Install ADV (Advance) spec-driven development plugin.
4. Install `omp` (opencode-model-preferences) model-routing TUI.
5. Sync OpenCode agent files, slash commands, and global instruction files.
6. Suggest adding `alias oc='open-chad'` to your `.zshrc`.

### Prerequisites

| Tool | Required | Notes |
|------|----------|-------|
| `bash` | Yes | 4.0+ |
| `git` | Yes | For cloning ADV and tmux config |
| `tmux` | Yes | 3.2+ recommended |
| `node` / `npm` | Yes | For JSON config merging |
| `pnpm` | Yes (ADV) | `npm install -g pnpm` to install |
| `go` | Yes (omp) | 1.16+ — `go install` used for omp |
| `opencode` | Yes | Install from https://opencode.ai |
| `jq` | Yes | Used by metrics collector for JSON parsing — not required by render path |

### What gets installed

- `~/.local/bin/open-chad` — symlink to the launcher
- `~/.local/bin/omp` — opencode-model-preferences binary
- `~/dev/oc-plugins/advance/` — ADV spec-driven dev plugin (cloned from GitHub)
- `~/.config/opencode/agents/` — agent markdown files (scout, refine, librarian, explore)
- `~/.config/opencode/command/adv-*.md` — ADV slash commands (synced from checkout)
- `~/.config/opencode/instructions/` — global instruction files (shell_strategy, mcp-tools, worktree-guide, lbp)
- `~/.config/opencode/themes/ayu-dark.json` — ayu-dark color theme
- `~/.config/opencode/opencode.json` — ADV plugin path, instruction paths, and theme merged in (additive only)

### Opt-out flags

```bash
# Skip ADV plugin install (keep existing ADV setup)
./install.sh --no-adv

# Skip omp install
./install.sh --no-omp

# Skip all OpenCode config changes (agents, commands, instructions, opencode.json)
./install.sh --no-opencode-setup

# Skip everything new (tmux + symlink only)
./install.sh --no-adv --no-omp --no-opencode-setup
```

### Re-running install (idempotent)

`install.sh` is safe to re-run. It will:
- Re-create the `open-chad` symlink (replacing any stale one)
- Skip the tmux theme if already present
- `git pull` the ADV checkout instead of re-cloning
- Re-run `pnpm install + build` in the ADV plugin directory
- Skip `omp` re-install if the same version is current (`go install` is idempotent)
- Re-sync agent, command, instruction, and theme files (overwrites with latest bundle)
- Re-merge opencode.json without duplicating existing entries

## Usage

```bash
# Launch OpenCode in current directory with animation
oc

# Launch in specific directory
oc ~/dev/my-project

# Skip the boot animation
oc --no-anim

# List all running OpenCode sessions and their memory usage
oc-list

# Kill all OpenCode sessions
oc-killall
```

## Architecture

- `bin/open-chad`: Main entrypoint. Handles arg parsing, animation trigger, metrics collector bootstrap, and tmux session isolation.
- `lib/animation.sh`: Pure bash boot animation using ayu-dark true-color ANSI sequences.
- `lib/collect_metrics.sh`: Singleton daemon. Writes `/tmp/open-chad-metrics` (CPU/RAM/load) every 30s. Writes 4 per-provider LLM quota cache files every 30s: `/tmp/open-chad-zai`, `/tmp/open-chad-copilot`, `/tmp/open-chad-claude`, `/tmp/open-chad-codex`. Each file contains a plain integer 0–100 (remaining %), or is empty when the provider is unavailable. Auth tokens are read from `~/.local/share/opencode/auth.json` at runtime. Uses PID locks and safe parallel background jobs (`wait $pid || rc=$?`).
- `lib/status_left.sh`: Fast tmux `#()` renderer. Reads 4 per-provider cache files (no jq, no curl — plain bash), applies per-segment color thresholds, composes 4-segment gauge with `title_parser.sh` output.
- `lib/status_right.sh`: Fast tmux `#()` renderer. Reads system metrics cache.
- `lib/title_parser.sh`: Fast tmux `#()` renderer. Parses ADV string structures.
- `lib/theme.conf`: Sourced by `~/.tmux.conf`.

## LLM Provider Auth

The metrics collector reads auth tokens from `~/.local/share/opencode/auth.json` at runtime. Each provider uses a specific key path:

| Provider | auth.json key | API endpoint |
|----------|--------------|--------------|
| Z.ai | `zai-coding-plan.key` | `api.z.ai/api/monitor/usage/quota/limit` |
| GitHub Copilot | `github-copilot.access` | `api.github.com/copilot_internal/user` |
| Claude (Anthropic) | `anthropic.access` | `api.anthropic.com/api/oauth/usage` |
| OpenAI Codex | `openai.access` | `chatgpt.com/backend-api/wham/usage` |

If a token is missing or the API call fails, that provider's segment shows `--` — no crash, no effect on other providers.

## License

MIT
