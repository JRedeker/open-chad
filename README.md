# open-chad

A retro tmux launcher and orchestrator for [OpenCode](https://github.com/opencode-ai/opencode).

Designed for developers who run 5-10+ concurrent OpenCode sessions and need instant visual context when switching tabs.

## Features

- **Boot Animation**: Muted 80s Apple/Amiga color-cycling logo and CRT scanline sweep (skippable via `--no-anim`).
- **Unified Retro Monitor**: Transforms tmux into a 2-row retro display (sage, gold, coral, brick, lavender, steel).
- **Smart Context Bar**: 
  - Left: ADV window title parser (extracts `EMOJI REPO CHANGE_ID` into structured zones).
  - Right: Live git branch + dirty state.
- **Shared System Metrics**: Background singleton collector tracks CPU%, RAM%, and Load Avg across all sessions with near-zero overhead.
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
2. Update your `~/.tmux.conf` to source the retro theme.
3. Suggest adding `alias oc='open-chad'` to your `.zshrc`.

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
- `lib/animation.sh`: Pure bash ANSI escape sequence port of the `x` Rust launcher.
- `lib/collect_metrics.sh`: Singleton daemon. Writes `/tmp/open-chad-metrics` every 30s. Uses `pgrep` and PID locks.
- `lib/status_right.sh`: Fast tmux `#()` renderer. Derives git state and reads metrics cache.
- `lib/title_parser.sh`: Fast tmux `#()` renderer. Parses ADV string structures.
- `lib/theme.conf`: Sourced by `~/.tmux.conf`.

## License

MIT
