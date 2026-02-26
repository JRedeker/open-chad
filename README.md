# openchad

**A context engineering platform for AI-assisted development.** One install gives you a complete environment where every layer — agents, rules, tools, specs, and instructions — is designed to shape what your AI sees, what it can do, and how it behaves.

For developers who run multiple concurrent AI coding sessions and want everything configured out of the box.

Built for [OpenCode](https://github.com/opencode-ai/opencode). Inspired by [NvChad](https://github.com/NvChad/NvChad). Color theme by [opencode-ayu-theme](https://github.com/postrednik/opencode-ayu-theme), based on [ayu](https://github.com/ayu-theme/ayu).

![openchad screenshot](Screenshot.png)

---

## Context Engineering, Out of the Box

AI coding tools are only as good as the context they operate in. openchad ships a complete context engineering stack so your agents start every session with the right knowledge, the right tools, and the right constraints — no manual wiring required.

### Layered Instructions & Rules
A priority-ranked rule system (25 rules, conflict resolution by priority) governs every agent interaction. Layered instruction files — identity, coding conventions, shell strategy, tool selection guides, TDD policy — are injected into every session automatically. Your agents follow your standards from the first prompt.

### Scoped Agent Orchestration
Eight specialized agents — **scout**, **build**, **refine**, **plan**, **explore**, **librarian**, **general**, and **adv-researcher** — each with explicitly scoped tool access. Scout is read-only. Plan blocks all writes. Refine has full access but is scope-locked to one objective. The right agent gets the right tools and nothing more.

### Spec-Driven Development (ADV)
The [ADV plugin](https://github.com/Sharper-Flow/Advance) turns requirements into enforceable specs. A 6-gate quality workflow — research → prep → implementation → review → harden → signoff — ensures changes are validated against specs before archive. Accumulated wisdom carries forward across changes.

### Pre-Wired Tool Ecosystem
MCP servers for documentation lookup ([Context7](https://context7.com)), code search ([grep.app](https://grep.app)), semantic codebase search ([lgrep](https://github.com/Sharper-Flow/lgrep)), and web scraping (Firecrawl) are configured and ready. Agents can reach external knowledge without you wiring anything.

The [Vision](https://github.com/Sharper-Flow/vision) MCP daemon is bundled and managed automatically — started as a singleton on every `openchad` launch, restarted on `openchad update`, and health-checked by `openchad doctor`. No manual daemon management required.

### Project Context via AGENTS.md
Each project gets an `AGENTS.md` that documents architecture, conventions, data flow, and design decisions. Agents read it automatically — so they understand your codebase structure, not just the code.

---

## What Else You Get

### Zsh Shell Environment
Installs zsh with [Powerlevel10k](https://github.com/romkatv/powerlevel10k), [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), and [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting) — configured and ready. Shell completions for all openchad commands included.

### Live LLM Fuel Gauges
See remaining quota for Z.ai, GitHub Copilot, Claude, and OpenAI Codex directly in your tmux status bar. Color-coded: green ≥50%, yellow 20–49%, red <20%. Updated every 30 seconds.

### Crash-Isolated Sessions
Every OpenCode instance runs in its own tmux session (`oc-<timestamp>-<pid>`). If one crashes, the rest are unaffected. Run 5, 10, or 20+ concurrent sessions without cascade failures.

### Themed tmux Dashboard
Two-row ayu-dark status bar with repo/branch context, session titles correlated from OpenCode's database, live system metrics (CPU, RAM, load), and a retro boot animation.

### Model Preferences (`omp`)

A terminal UI for managing OpenCode model preferences — switch models, set defaults, and configure per-project overrides without editing JSON.

![omp model preferences](ompscreenshot.png)

### Discord Rich Presence
Optional — show your openchad activity in Discord with a single command. No Discord Developer account required.

```bash
openchad discord enable          # Enable with built-in default app (no setup needed)
openchad discord enable --custom # Use your own Discord app (advanced)
openchad discord status          # Check current mode and last update time
```

All dynamic input is sanitized — no project names, file paths, tokens, or secrets are ever transmitted. See [`lib/discord/SETUP.md`](lib/discord/SETUP.md) for the full guide.

---

## Install

Two commands on a fresh Ubuntu/Debian system:

```bash
git clone https://github.com/JRedeker/open-chad.git && cd open-chad
bash install.sh
```

The interactive wizard walks you through 10 steps:

| Step | What happens |
|------|-------------|
| 1 | System dependencies (git, curl, tmux, Node 20, pnpm) |
| 2 | OpenCode OAuth onboarding |
| 3 | Dev language bundles — Python (uv), Go, Rust, Web (TS/JS) |
| 4 | MCP servers wired into opencode.json |
| 5 | Vision MCP daemon registered and started |
| 6 | ADV + morph plugins installed |
| 7 | Agents, instructions, theme, slash commands synced |
| 8 | Model preferences TUI (`omp`) |
| 9 | Zsh + plugins configured |
| 10 | Windows Terminal keybindings (WSL only) |

For CI or unattended installs: `bash install.sh --yes`

After install, reload your shell (`source ~/.zshrc` or `source ~/.bashrc`) and you're ready.

### Update

```bash
openchad update
```

Pulls latest changes and re-runs all setup modules. Safe to run anytime.

### Verify

After launching OpenCode, paste the verification prompt from `~/.config/opencode/instructions/post_install_verification.md` to confirm everything is wired correctly.

### Uninstall

```bash
openchad uninstall
```

Removes symlinks and shell profile blocks. Your OpenCode config and plugins are left intact.

### Upgrading from `open-chad`

The command was renamed from `open-chad` to `openchad`. Running `openchad update` or `bash install.sh` auto-cleans stale aliases and PATH entries. Run `openchad doctor` to verify.

---

## Worktree Flow

When the ADV plugin creates a git worktree for an isolated change, openchad may open a new tmux window for it. The agent continues working inline — but you can navigate to the new tab with:

| Key | Action |
|-----|--------|
| `Ctrl+b n` | Next tmux window |
| `Ctrl+b l` | Last (previously active) window |
| `Ctrl+b w` | Interactive window chooser |
| `oc switch` | Switch between openchad sessions |

The agent emits this hint automatically after every `worktree_create` so you never have to remember the keybinds.

---

## Usage

```bash
openchad                        # Launch in current directory
openchad ~/dev/my-project       # Launch in specific directory
openchad --no-anim              # Skip boot animation

oc                              # Short alias (same as openchad)
oc x                            # Launch ~/dev/x from any directory
oc my-project --no-anim         # Launch ~/dev/my-project, skip animation
oc attach                       # Attach to a running session
oc switch                       # Pick a session to switch to

cds                             # Create ~/scratch/YYYY-MM-DD and launch there
cds 2026-01-15                  # Specific date

oc-list                         # List all running sessions
oc-killall                      # Kill all sessions (--yes to skip prompt)
```

### Project shorthand (`oc <name>`)

`oc` resolves bare project names to directories under `~/dev` so you can launch
from anywhere without `cd`:

```bash
oc x                  # → ~/dev/x
oc morph-fast-apply   # → ~/dev/oc-plugins/morph-fast-apply (one level deep)
oc shared             # → error: lists all matches if ambiguous
```

**Resolution precedence** (highest to lowest):

| Priority | Condition | Behavior |
|----------|-----------|----------|
| 1 | Subcommand (`update`, `doctor`, `version`, …) | Forwarded unchanged |
| 2 | Explicit path (`./x`, `../x`, `/abs`, `~/…`) | Forwarded unchanged |
| 3 | `~/dev/<name>` exists | Resolved to that path |
| 4 | Exactly one `~/dev/*/<name>` exists | Resolved with a stderr notice |
| 5 | Multiple `~/dev/*/<name>` exist | Exit 1 + disambiguation list |
| 6 | No match | Forwarded unchanged (openchad handles the error) |

Tab-completion offers project names from `~/dev` alongside subcommands, with
de-dup behavior: if a name exists both top-level and nested, only the top-level
name is suggested (matching runtime resolution precedence).

### Subcommands

```bash
openchad version                # Show version
openchad doctor                 # Validate install health
openchad update                 # Pull latest + re-run setup
openchad uninstall              # Remove openchad
openchad metrics                # Show system metrics
openchad metrics log            # Append timestamped reading to history
openchad metrics export         # Print as JSON
openchad changelog              # Git log since last tag
openchad changelog latest       # Show last tag release notes
openchad discord enable         # Turn on Discord Rich Presence
openchad discord status         # Check Discord status
```

### CI/CD and Releases

- CI runs on every PR and every push to `trunk` (`.github/workflows/ci.yml`) and executes the full `npm test` suite.
- Release automation runs on version tags (`v*`) (`.github/workflows/release.yml`). It gates on passing tests, then:
  - generates release notes from commits since the previous tag,
  - updates `CHANGELOG.md` in the packaged artifact,
  - builds `openchad-<tag>.tar.gz` + `SHA256SUMS.txt`,
  - publishes a GitHub Release with all artifacts attached.

To cut a release:

```bash
git tag v1.2.3
git push origin v1.2.3
```

---

## Configuration

### LLM Provider Gauge

The fuel gauge auto-detects providers from your auth tokens in `~/.local/share/opencode/auth.json`. To show only specific providers, add to `~/.config/opencode/open-chad.json`:

```json
{
  "providers": ["zai", "claude"]
}
```

Valid IDs: `zai`, `copilot`, `claude`, `codex`.

To disable the gauge entirely: `export OPEN_CHAD_MULTI_GAUGE=0`

### Re-running Install

`install.sh` is idempotent — safe to re-run anytime. It re-syncs config, pulls latest plugins, and merges opencode.json without duplicating entries.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `openchad: command not found` | Reload shell: `source ~/.zshrc` or `source ~/.bashrc` |
| opencode.json parse error | See [recovery steps](AGENTS.md#recovering-from-opencodejson-conflicts) |
| ADV plugin not loading | `bash lib/setup_adv.sh` |
| Missing MCP server | Check `~/.config/opencode/opencode.json` for the server entry |
| Theme looks wrong | `bash lib/setup_opencode.sh` |
| Vision MCP tools unavailable | Run `openchad doctor` to check daemon status; ensure `vision` binary is on PATH |
| `openchad doctor` reports issues | Follow the remediation instructions it prints |

For detailed installer internals, CI flags, architecture, and contributor docs, see [AGENTS.md](AGENTS.md).

---

## Requirements

- **Ubuntu / Debian** (Linux only — uses `/proc` for system metrics)
- **bash 4.0+**, **git**, **tmux 3.2+**
- **Node.js / npm** (for config merging)
- **OpenCode** — install from [opencode.ai](https://opencode.ai)

Everything else is installed automatically by the wizard.

---

## License

MIT
