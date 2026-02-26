# AGENTS.md — Developer & Agent Reference

Internal reference for AI agents and human developers working on open-chad.
For user-facing documentation, see [README.md](README.md).

---

## Project Overview

**open-chad** is a tmux-powered command center for [OpenCode](https://github.com/opencode-ai/opencode). It wraps each OpenCode session in an isolated tmux session with a themed two-row status bar, boot animation, live LLM quota gauges, system metrics, and optional Discord Rich Presence.

- **Repo**: `https://github.com/JRedeker/open-chad.git`
- **Branch**: `trunk` (default), remote `origin`
- **Language**: Bash (all runtime scripts), Node.js (JSON merge, Discord RPC), Python (SQLite queries)
- **Test framework**: Plain bash — no bats, no npm test runners

---

## Architecture

```
bin/
  open-chad                 Entrypoint — arg parsing, animation, metrics bootstrap,
                            tmux session creation (oc-<epoch>-<pid>)

lib/
  opencode_env.sh           Cache dir setup (XDG_RUNTIME_DIR/open-chad or /tmp fallback).
                            Sourced by most scripts. Exports OPEN_CHAD_CACHE_DIR.
  animation.sh              Boot animation — centered logo, 6-frame color cycling,
                            typewriter subtitle, project context. True-color ANSI.
  theme.conf                Tmux theme — 2-row ayu-dark layout, sourced by ~/.tmux.conf
  session_title.sh          Row 0 left — queries OpenCode SQLite DB for session title,
                            correlates by tmux launch timestamp (no cross-session bleed)
  status_resources.sh       Standalone resource renderer (CPU%, RAM%, Load) — available
                            for custom layouts; Row 1 uses status_right.sh which includes
                            resources inline alongside LLM gauges.
  status_left.sh            Row 1 left — renders worktree / branch for current pane
  status_right.sh           Row 1 right — renders CPU%, RAM%, Load + 4-provider LLM fuel
                            gauges as one unit. OPEN_CHAD_MULTI_GAUGE toggle supported.
  title_parser.sh           Parses ADV state strings (emoji + repo + changeId) for
                            structured tmux display in window name area
  collect_metrics.sh        Singleton background daemon — writes system metrics and
                            per-provider LLM quota to cache files every 30s.
                            PID-locked, parallel API calls, atomic writes.
  json_merge.sh             Idempotent additive JSON merge (Node.js). Arrays deduped,
                            scalars only added if not present, nested objects recursed.
  setup_adv.sh              ADV plugin installer (pnpm)
  setup_omp.sh              Model preferences TUI installer (go build)
  setup_opencode.sh         OpenCode config/agent/theme sync
  discord/
    setup.sh                Discord Rich Presence wizard + CLI (enable/disable/status)
    update.sh               Rate-limited bridge — checks config, rate limit, calls update.js
    update.js               Short-lived Node.js process — connects to Discord IPC,
                            sends one SET_ACTIVITY, exits. Sanitizes all dynamic input.
    taglines.sh             Rotating tagline selector with no-repeat guard
    SETUP.md                User-facing Discord setup guide

  Installer (v1.0):
  check_environment.sh      Pre-flight: OS (Ubuntu/Debian), git, 500MB disk, conflicts.
                            Called by install.sh and update.sh before any changes.
  setup_ubuntu_deps.sh      Silent apt bootstrap — core tools + language toolchain prereqs.
                            DEBIAN_FRONTEND=noninteractive, logs to /tmp/open-chad-install.log.
  setup_mcp.sh              Wires 5 MCP servers into opencode.json via json_merge.sh.
                            context7/grep-app/lgrep/firecrawl registered as type=remote
                            pointing at Vision daemon ports (6276/6288/6285/6281).
                            brave-web-search registered as type=local (disabled, key-required).
                            context7/grep-app/lgrep enabled; firecrawl/brave-web-search disabled.
                            Validates JSON before and after merge.
  setup_morph.sh            Clone/pull morph-fast-apply, pnpm install+build, wire plugin
                            path and MORPH_INSTRUCTIONS.md into opencode.json.
  setup_dev_bundle.sh       Python (uv-only, no pyenv), Go (apt+tarball), Rust (rustup).
                            Pyrefly wired as LSP. Persists selectedBundles to
                            ~/.config/opencode/open-chad.json under installer key.
  setup_opencode_auth.sh    Step-by-step Claude OAuth onboarding. --check, --no-wait flags.
  setup_zsh_plugins.sh      Zsh + plugin setup — installs zsh via apt, clones
                            romkatv/powerlevel10k, zsh-users/zsh-autosuggestions,
                            zdharma-continuum/fast-syntax-highlighting into
                            ~/.zsh/plugins/. Writes idempotent OPEN-CHAD ZSH BEGIN/END
                            block to ~/.zshrc (plugin order: p10k → autosuggestions →
                            fast-syntax-highlighting). Opt-in chsh prompt in interactive
                            mode. Called by wizard.sh (Step 8) and update.sh (non-fatal).
  update.sh                 `open-chad update` backend: git pull --ff-only, re-runs all
                            setup modules. .git detection + releases URL. Diverged branch
                            recovery guide (reset --hard / stash / rebase).
  wizard.sh                 Interactive 9-step install wizard. YES_MODE for CI/--yes.
                            Logs to ~/.config/opencode/open-chad-install.log. Flags:
                            --yes, --skip-deps/auth/bundles/mcp/adv/morph/omp/zsh, --verbose.

bin/
  open-chad                 Main launcher — animation, metrics bootstrap, tmux session
  cds                       Date-stamped scratch directory launcher
  oc-list                   List active oc-* tmux sessions with window count and memory
  oc-killall                Kill all oc-* tmux sessions (--yes to skip confirmation)

config/
  opencode/
    agents/                 Agent markdown files (scout, refine, librarian, explore,
                            build, general, plan, adv-researcher).
                            refine: full tool access, scope-locked; owns /adv-prep and
                            /adv-harden gates including investigation, architectural
                            decisions, and implementation of fixes found.
                            adv-researcher: hidden sub-agent for /adv-research; validates
                            architectural decisions via Context7 and web search. Bundled
                            as fallback; upstream copy synced from ADV checkout when present.
    instructions/           Global instruction files (identity, rules, lbp, mcp-tools,
                            shell_strategy, worktree-guide)
    themes/ayu-dark.json    OpenCode color theme

tests/
  animation_test.sh         39 tests — centering math, palette, phases, regression guards
  session_title_test.sh     31 tests — SQLite correlation, no-fallback, filtering, format
  llm_fuel_test.sh          50 tests — gauge rendering, API parsing, toggle, edge cases
  install_test.sh           104 tests — idempotency, flags, file creation, MCP regression
  installer_validation_test.sh  82 tests — error paths, wizard flags, MCP schema/enabled/disabled,
                            dev bundle config persistence
  discord_sanitizer_test.sh 34 tests — sanitizer pattern matching
  discord_setup_test.sh     20 tests — setup wizard, config read/write

docs/
  STATUS_BAR_IMPLEMENTATION.md   Implementation examples for status bar data sources
  STATUS_BAR_SOURCES.md          Available data sources and priority matrix
```

---

## Color Palette (ayu-dark)

All UI elements use the ayu-dark palette. Use these exact hex values:

| Name | Hex | Usage |
|------|-----|-------|
| `string` | `#AAD94C` | Green — accent edges, active pane border, healthy gauge |
| `accent` | `#E6B450` | Golden yellow — accent edges, project name, mid gauge |
| `type` | `#59C2FF` | Blue — accent edges, subtitle, git branch |
| `keyword` | `#FF8F40` | Orange — accent edges, low gauge |
| `func` | `#FFB454` | Functions orange — activity indicator |
| `comment` | `#626d7a` | Gray — labels, separators, system metrics |
| `fg` | `#BFBDB6` | Foreground — primary text, session title |
| `bg` | `#0D1017` | Background — status bar, pane background |
| `line` | `#161A24` | Lifted background — active tab |
| `border` | `#1B1F29` | Separators, inactive elements |

### True-color ANSI (for bash scripts)

```bash
C_STRING=$'\e[38;2;170;217;76m'      # #AAD94C
C_ACCENT=$'\e[38;2;230;180;80m'      # #E6B450
C_TYPE=$'\e[38;2;89;194;255m'        # #59C2FF
C_KEYWORD=$'\e[38;2;255;143;64m'     # #FF8F40
C_FUNC=$'\e[38;2;255;180;84m'        # #FFB454
C_COMMENT=$'\e[38;2;98;109;122m'     # #626d7a
C_FG=$'\e[38;2;191;189;182m'         # #BFBDB6
C_RESET=$'\e[0m'
```

### Tmux format colors

Use hex directly in tmux format strings: `#[fg=#AAD94C]`, `#[bg=#0D1017]`.

---

## Status Bar Layout

Two-row tmux status bar, both rows on `bg=#0D1017`:

### Row 0 (main status line)

| Position | Content | Script |
|----------|---------|--------|
| Left | `▌▌▌▌` accent edges → window name → `│` → session title | `session_title.sh` |
| Center | Tab bar (inactive: comment gray, active: lifted bg) | `theme.conf` |
| Right | HH:MM `│` DD-Mon → `▐▐▐▐` accent edges | `theme.conf` |

### Row 1 (detail line)

| Position | Content | Script |
|----------|---------|--------|
| Left | `▌▌▌▌` accent edges → worktree / branch | `status_left.sh` |
| Right | Z.ai NN% `│` Copilot NN% `│` Claude NN% `│` Codex NN% → `▐▐▐▐` | `status_right.sh` |

### Accent edge pattern

Left edges: `▌` in green → golden → blue → orange (4 chars)
Right edges: `▐` in orange → blue → golden → green (4 chars, reversed)

---

## Data Flow

### System Metrics

```
collect_metrics.sh (singleton, every 30s)
  ├─ /proc/stat → CPU%
  ├─ /proc/meminfo → RAM%
  ├─ /proc/loadavg → Load
  └─ writes "$OPEN_CHAD_CACHE_DIR/metrics" (space-separated: "CPU RAM LOAD")

status_resources.sh (called by tmux every 5s)
  └─ reads "$OPEN_CHAD_CACHE_DIR/metrics" → tmux format string
```

### LLM Quota

```
collect_metrics.sh (singleton, every 30s, parallel)
  ├─ Z.ai API → $OPEN_CHAD_CACHE_DIR/zai (integer 0-100)
  ├─ GitHub Copilot API → $OPEN_CHAD_CACHE_DIR/copilot
  ├─ Anthropic API → $OPEN_CHAD_CACHE_DIR/claude
  └─ OpenAI API → $OPEN_CHAD_CACHE_DIR/codex

status_right.sh (called by tmux every 5s)
  └─ reads 4 cache files → tmux format string with color thresholds
```

### Session Title Correlation

```
bin/open-chad creates tmux session: "oc-<epoch_seconds>-<pid>"

session_title.sh (called by tmux every 5s)
  ├─ extracts epoch from session name via regex
  ├─ queries OpenCode SQLite DB:
  │     SELECT title FROM session
  │     WHERE directory = <worktree>
  │       AND parent_id IS NULL
  │       AND time_created BETWEEN <epoch_ms> AND <epoch_ms + 120000>
  │     ORDER BY time_created ASC LIMIT 1
  └─ no match = empty output (never guesses wrong)
```

### Discord Rich Presence

```
bin/open-chad (on launch, fire-and-forget)
  └─ update.sh (rate-limited, 15s cooldown via lockfile mtime)
       ├─ reads config from ~/.config/opencode/open-chad.json
       ├─ checks discordPresence.enabled
       ├─ picks tagline via taglines.sh (no-repeat guard)
       └─ update.js (short-lived Node.js process)
            ├─ sanitizes all dynamic input
            ├─ connects to Discord IPC (8s timeout)
            ├─ sends SET_ACTIVITY
            └─ exits 0 (always — Discord not running is non-fatal)
```

---

## Cache Directory

Resolved by `opencode_env.sh`:

| Priority | Path | When |
|----------|------|------|
| 1 | `$OPEN_CHAD_CACHE_DIR` (if pre-set) | Testing, custom installs |
| 2 | `$XDG_RUNTIME_DIR/open-chad` | Linux with systemd |
| 3 | `/tmp/open-chad-$USER` | macOS, containers |

Permissions: `0700` (owner-only). Created on first source.

### Cache files

| File | Content | Writer | Reader |
|------|---------|--------|--------|
| `metrics` | `CPU% RAM% LOAD` (space-separated) | `collect_metrics.sh` | `status_resources.sh` |
| `metrics.lock` | PID of running collector | `collect_metrics.sh` | `collect_metrics.sh` (singleton guard) |
| `metrics-start.lock` | Atomic mkdir startup lock | `bin/open-chad` | `bin/open-chad` (prevents duplicate collector starts) |
| `zai` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `copilot` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `claude` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `codex` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |

All writes are atomic (write to `$file.$$`, then `mv -f`).

---

## Testing

### Framework

Plain bash. Each test file is self-contained with helpers:

```bash
pass()            # Increment pass counter, print green checkmark
fail()            # Increment fail counter, print red X with message
assert_eq()       # Compare two values, pass/fail
assert_contains() # Check substring, pass/fail
section()         # Print section header
```

Exit code = number of failures (0 = all pass).

### Running tests

```bash
# All tests (via npm — runs all 13 suites):
npm test

# Or run individual suites:
bash tests/install_test.sh
bash tests/llm_fuel_test.sh
bash tests/animation_test.sh
bash tests/session_title_test.sh
bash tests/discord_sanitizer_test.sh
bash tests/discord_setup_test.sh
bash tests/installer_validation_test.sh
bash tests/cds_test.sh
bash tests/integration_test.sh
bash tests/installer_robustness_test.sh
bash tests/setup_zsh_test.sh
bash tests/shell_profile_test.sh
bash tests/oc_sessions_test.sh
```

### Test counts

| Suite | Tests | What it covers |
|-------|-------|----------------|
| `install_test.sh` | 104 | Idempotency, flags, file creation, MCP regression, oc-list/oc-killall symlinks |
| `llm_fuel_test.sh` | 62 | Gauge rendering, API parsing, toggle, edge cases |
| `animation_test.sh` | 39 | Centering math, palette, phases, regression guards |
| `session_title_test.sh` | 31 | SQLite correlation, no-fallback, filtering, format |
| `installer_validation_test.sh` | 82 | Error paths, wizard flags, MCP schema/enabled/disabled, bundle config |
| `discord_sanitizer_test.sh` | 34 | Sanitizer pattern matching |
| `discord_setup_test.sh` | 20 | Setup wizard, config read/write |
| `cds_test.sh` | 18 | Date-stamped scratch dir launcher |
| `integration_test.sh` | 11 | End-to-end installer flow |
| `installer_robustness_test.sh` | 24 | Scenario-driven robustness |
| `setup_zsh_test.sh` | 32 | Zsh plugin setup, managed .zshrc block |
| `shell_profile_test.sh` | 27 | Shell profile PATH wiring |
| `oc_sessions_test.sh` | 29 | oc-list and oc-killall behavior |
| **Total** | **513** | |

### Testing conventions

- Tests source the script under test (or extract functions) — they don't shell out to the full script
- Mock external dependencies (git, python3, SQLite) by overriding functions or providing fake data
- Use `OPEN_CHAD_CACHE_DIR` override to isolate cache in `/tmp/test-*` directories
- Clean up temp dirs in trap handlers

---

## LLM Provider API Reference

Auth tokens are read from `~/.local/share/opencode/auth.json`.

| Provider | auth.json key | API endpoint | Response → remaining% |
|----------|--------------|--------------|----------------------|
| Z.ai | `["zai-coding-plan"].key` | `GET api.z.ai/api/monitor/usage/quota/limit` | `100 - data.limits[type=TOKENS_LIMIT].percentage` |
| GitHub Copilot | `["github-copilot"].access` | `GET api.github.com/copilot_internal/user` | `quota_snapshots.premium_interactions.percent_remaining` (clamped 0-100) |
| Claude | `["anthropic"].access` | `GET api.anthropic.com/api/oauth/usage` | `100 - five_hour.utilization` |
| OpenAI Codex | `["openai"].access` | `GET chatgpt.com/backend-api/wham/usage` | `100 - rate_limit.primary_window.used_percent` |

### Gauge color thresholds

| Range | Color | Hex |
|-------|-------|-----|
| >= 50% | Green | `#AAD94C` |
| 20-49% | Yellow | `#E6B450` |
| < 20% | Orange/Red | `#FF8F40` |
| No data | Gray `--` | `#626d7a` |

---

## Key Design Decisions

### Session isolation

Each `open-chad` invocation creates a unique tmux session: `oc-<epoch_seconds>-<pid>`. If one OpenCode instance crashes, others are unaffected. The epoch is embedded in the session name to enable timestamp-based correlation with the OpenCode SQLite DB.

### No fallback in session title

`session_title.sh` deliberately has **no fallback query**. If the timestamp correlation doesn't find a match within the 120-second window, it outputs nothing. A previous fallback that grabbed the most recently created session caused cross-session title bleed (wrong titles rotating across tabs).

### Singleton metrics collector

`collect_metrics.sh` uses a PID lockfile to ensure only one instance runs across all tmux sessions. All sessions read from the same cache files. The 1-second CPU sample (via `/proc/stat` delta) runs inside the collector's 30-second loop, not in the render path.

### Render path has zero external dependencies

`status_right.sh`, `status_left.sh`, and `status_resources.sh` read only from cache files using plain bash `read` and `cat`. No `jq`, no `curl`, no `python3` in the render path. This keeps tmux responsive even with 10+ sessions.

### Atomic cache writes

All cache writes use the pattern: write to `$file.$$` (temp with PID suffix), then `mv -f` to the final path. This prevents readers from seeing partial writes.

### Discord sanitizer

All dynamic input to Discord RPC passes through a sanitizer that redacts: home directory paths, environment variables, API tokens (sk-*, ghp_*, AKIA*), and long opaque strings (20+ alphanumeric chars). Nothing sensitive is ever transmitted.

---

## Conventions

### Bash style

- `set -euo pipefail` in all scripts
- ShellCheck clean (where practical)
- Functions prefixed with `_` are internal (not part of public interface)
- Exit 0 on missing data (graceful degradation, never crash tmux)

### Git

- Branch: `trunk` (not `main`)
- Commit style: conventional commits (`feat:`, `fix:`, `test:`, `docs:`)
- Remote: `origin` → `https://github.com/JRedeker/open-chad.git`

### File naming

- Scripts: `snake_case.sh`
- Config: `snake_case.conf` or `camelCase.json`
- Tests: `<module>_test.sh`

---

## Security Hardening (v1.1)

The following security fixes were applied in the v1.1 hardening pass:

| ID | Script | Fix |
|----|--------|-----|
| CVE-001 | `bin/open-chad`, `lib/discord/update.sh` | Discord lockfile moved from `/tmp` to `$OPEN_CHAD_CACHE_DIR` (user-private). Legacy `/tmp/discord-rpc.lock*` cleaned up on startup with symlink-safe deletion guards. |
| CVE-002 | `lib/setup_dev_bundle.sh` | Go tarball SHA256 verified before `sudo rm -rf /usr/local/go`. Requires `sha256sum`; aborts on mismatch or missing checksum file. |
| CVE-003 | `lib/setup_mcp.sh` | Removed silent `opencode.json` auto-wipe in `--yes` mode. Invalid JSON now exits with `ERROR:` + recovery instructions. See README for recovery procedure. |
| CVE-004 | `lib/setup_opencode.sh` | Symlink sources rejected during agent/instruction/theme file copy. Symlinks are skipped with a `WARN:` message. |
| CVE-005 | `bin/open-chad` | Discord `update.sh` stderr now logged to `$OPEN_CHAD_CACHE_DIR/discord.log` (0600) instead of `/dev/null`. |
| ISSUE-006 | `install.sh`, `lib/update.sh` | Symlink creation changed to atomic `ln -sfn`. Source existence validated before linking. |
| ISSUE-008 | `lib/wizard.sh` | Install log created with `install -m 0600` for atomic secure creation. |
| ISSUE-009 | `lib/setup_mcp.sh` | Node.js invocations use `process.argv` file inputs (not interpolated strings) for path safety. |
| ISSUE-010 | `bin/open-chad` | Metrics collector singleton guard changed from `pgrep -f` to atomic `mkdir` lockdir (`metrics-start.lock`). Renamed from `metrics.lock` to avoid collision with the collector's own PID lockfile. Lockdir removed after 2s delay to close the race window. |
| ISSUE-011 | `lib/setup_dev_bundle.sh` | Go fallback version updated to `go1.26.0` with maintenance comment. |
| ISSUE-012 | `lib/check_environment.sh` | Non-fatal `python3` presence check added with `apt install python3` hint. |
| ISSUE-013 | `lib/setup_dev_bundle.sh` | `_persist_bundles` moved to after failure checks — failed installs no longer persist as selected. |
| ISSUE-016 | `lib/json_merge.sh` | 1MB size guard added before Node.js parse for both target file and merge payload. |
| ISSUE-017 | `lib/wizard.sh` | WSL detected via `/proc/version`; generates `~/open-chad-keybindings.ps1` instead of manual instructions. |
| ISSUE-018 | `lib/setup_shell_profile.sh` | Exports PATH directly after writing block for immediate availability. Does NOT source the user's rc file (security: avoids executing arbitrary user shell code in installer context). |
| ISSUE-019 | `lib/collect_metrics.sh` | `find` cleanup wrapped in `timeout 5` to prevent hangs on slow filesystems. |
| ISSUE-021 | `lib/setup_shell_profile.sh` | Heredoc changed from `<<'EOF'` to `<<EOF` with `\$HOME` for explicit intent. |

### Behavioral changes in `--yes` mode

- **CVE-003**: `setup_mcp.sh` no longer silently wipes `opencode.json` on parse failure. It exits with an error and recovery instructions. This is a **breaking change** for automated installs with corrupted configs — fix the config first.

### New environment requirements

- **python3**: `check_environment.sh` now warns (non-fatal) if `python3` is missing. Required for `session_title.sh` SQLite lookup. Install with: `sudo apt install python3`

---

## Known Limitations

- **OpenCode TUI logo is not patchable** — the logo is dynamically generated at runtime inside a compiled Bun binary. No static string to replace. An upstream PR (#12017) for custom logo config exists but hasn't merged as of v1.2.10.
- **LLM quota APIs are undocumented** — endpoints were reverse-engineered from browser/editor traffic. They may change without notice.
- **Copilot percent_remaining can be negative** — when over quota. The collector clamps to 0.
- **Session title requires python3** — the SQLite query uses python3 for parameterized queries. This is the only script with a python3 dependency.
- **Linux-only for /proc metrics** — `collect_metrics.sh` reads `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`. macOS would need different implementations.
