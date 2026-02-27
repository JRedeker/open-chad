# AGENTS.md — Developer & Agent Reference

Internal reference for AI agents and human developers working on openchad.
For user-facing documentation, see [README.md](README.md).

---

## Project Overview

**openchad** is a tmux-powered command center for [OpenCode](https://github.com/opencode-ai/opencode). It wraps each OpenCode session in an isolated tmux session with a themed two-row status bar, boot animation, live LLM quota gauges, system metrics, and optional Discord Rich Presence.

> **Note:** The canonical command is `openchad` (one word). The short alias `oc` is also installed. The old hyphenated name `open-chad` is no longer used as a command — stale aliases and are auto-cleaned by `install.sh` and `openchad update`.

- **Repo**: `https://github.com/JRedeker/open-chad.git`
- **Branch**: `trunk` (default), remote `origin`
- **Language**: Bash (all runtime scripts), Node.js (JSON merge, Discord RPC), Python (SQLite queries)
- **Test framework**: Plain bash — no bats, no npm test runners

---

## Architecture

```
bin/
  openchad                  Entrypoint — thin dispatcher (case statement) routes
                            subcommands to dedicated handlers, then handles arg
                            parsing, animation, metrics bootstrap, tmux session
                            creation (oc-<epoch>-<pid>)
  oc                        Short alias — resolves bare project names under
                            ~/dev before forwarding to openchad; also provides
                            `oc attach` and `oc switch` session helpers
  cds                       Date-stamped scratch directory launcher
  oc-list                   List active oc-* tmux sessions with window count and memory
  oc-killall                Kill all oc-* tmux sessions (--yes to skip confirmation)

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
  status_right.sh           Row 1 right — renders CPU%, RAM%, Load + dynamic provider
                            LLM fuel gauges. Reads active_providers cache file for
                            provider list/order. OPEN_CHAD_MULTI_GAUGE toggle supported.
  title_parser.sh           Parses ADV state strings (emoji + repo + changeId) for
                            structured tmux display in window name area
  collect_metrics.sh        Singleton background daemon — writes system metrics and
                            per-provider LLM quota to cache files every 30s. Reads
                            provider config from open-chad.json, writes active_providers
                            cache. PID-locked, parallel API calls, atomic writes.
  json_merge.sh             Idempotent additive JSON merge (Node.js). Arrays deduped,
                            scalars only added if not present, nested objects recursed.
  openchad_version.sh       `openchad version` handler — git describe or hardcoded fallback
  openchad_doctor.sh        `openchad doctor` handler — validates PATH setup, tmux theme,
                            cache dir, legacy open-chad migration
  openchad_uninstall.sh     `openchad uninstall` handler — removes PATH block,
                            tmux theme block, shell profile blocks via manifest
  openchad_metrics.sh       `openchad metrics` handler — show/log/export system metrics
  openchad_changelog.sh     `openchad changelog` handler — git log since last tag
  setup_adv.sh              ADV plugin installer — reads config/opencode/adv-lock.json for
                            pinned commit SHA. Modes: pinned (default), latest, offline.
                            Two-tier fallback: network clone/build -> bundled command docs.
                            Non-fatal: all failures fall back to bundled and exit 0.
                            ADV_INSTALL_MODE env var controls mode.
  setup_omp.sh              Model preferences TUI installer (go build)
  setup_opencode.sh         OpenCode config/agent/theme sync
  setup_vision.sh           Vision MCP daemon setup — verifies vision binary on PATH
                            (non-fatal warn if missing), creates/merges
                            ~/.config/vision/servers.yaml with 4 MCP servers
                            (context7/grep-app/lgrep/firecrawl), sets 0600 perms,
                            reloads running daemon. Idempotent: skips servers already
                            present. Called by wizard.sh (Step 5) and update.sh.
  discord/
    setup.sh                Discord Rich Presence wizard + CLI (enable/disable/status)
    update.sh               Rate-limited bridge — checks config, rate limit, calls update.js
    update.js               Short-lived Node.js process — connects to Discord IPC,
                            sends one SET_ACTIVITY, exits. Sanitizes all dynamic input.
    taglines.sh             Rotating tagline selector with no-repeat guard
    SETUP.md                User-facing Discord setup guide

  Installer (v1.1):
  check_environment.sh      Pre-flight: OS (Ubuntu/Debian), git, 500MB disk, conflicts.
                            Called by install.sh and update.sh before any changes.
  setup_ubuntu_deps.sh      Silent apt bootstrap — core tools + language toolchain prereqs.
                            DEBIAN_FRONTEND=noninteractive, logs to /tmp/open-chad-install.log.
  setup_mcp.sh              Wires 5 MCP servers into opencode.json via json_merge.sh.
                            context7/grep-app/lgrep/firecrawl registered as type=remote
                            pointing at Vision daemon ports (6276/6288/6285/6281).
                            brave-web-search registered as type=local (disabled, key-required).
                            context7/grep-app/lgrep/firecrawl enabled; brave-web-search disabled.
                            Validates JSON before and after merge.
  setup_morph.sh            Clone/pull morph-fast-apply, pnpm install+build, wire plugin
                            path and MORPH_INSTRUCTIONS.md into opencode.json.
  setup_dev_bundle.sh       Python (uv-only, no pyenv), Go (apt+tarball), Rust (rustup).
                            Pyrefly wired as LSP. Persists selectedBundles to
                            ~/.config/opencode/open-chad.json under installer key.
  setup_opencode_auth.sh    Step-by-step Claude OAuth onboarding. --check, --no-wait flags.
  setup_shell_profile.sh    Wires ~/.local/bin PATH export and shell completions into
                            rc files. Backs up rc file before modifying.
  setup_zsh_plugins.sh      Zsh + plugin setup — installs zsh via apt, clones
                            romkatv/powerlevel10k, zsh-users/zsh-autosuggestions,
                            zdharma-continuum/fast-syntax-highlighting into
                            ~/.zsh/plugins/. Writes idempotent OPEN-CHAD ZSH BEGIN/END
                            block to ~/.zshrc (plugin order: p10k → autosuggestions →
                            fast-syntax-highlighting). Opt-in chsh prompt in interactive
                            mode. Called by wizard.sh (Step 8) and update.sh (non-fatal).
  update.sh                 `openchad update` backend: git pull --ff-only, re-runs all
                            setup modules, repairs via manifest, removes stale
                            open-chad aliases/PATH from rc files. .git detection +
                            releases URL. Diverged branch recovery guide.
  wizard.sh                 Interactive 10-step install wizard. YES_MODE for CI/--yes.
                            Logs to ~/.config/opencode/open-chad-install.log. Flags:
                            --yes, --skip-deps/auth/bundles/mcp/adv/morph/omp/zsh, --verbose.
                            Step 5 runs setup_vision.sh (Vision MCP daemon).

completion/
  openchad.bash             Bash completion for openchad and oc subcommands
  _openchad.zsh             Zsh completion for openchad and oc subcommands

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
                            shell_strategy, worktree-guide). worktree-guide includes
                            a "Navigating to the New Worktree Tab" section with tmux
                            keybinds (Ctrl+b n/l/w, oc switch) emitted by the agent
                            after every worktree_create.
    themes/ayu-dark.json    OpenCode color theme

Makefile                    Project task runner — install, test, verify, update, clean, uninstall

tests/
  animation_test.sh         39 tests — centering math, palette, phases, regression guards
  session_title_test.sh     31 tests — SQLite correlation, no-fallback, filtering, format
  llm_fuel_test.sh          72 tests — gauge rendering, API parsing, toggle, dynamic providers,
                            active_providers robustness, ordering
  install_test.sh           131 tests — idempotency, flags, file creation, MCP regression,
                            openchad/oc manifest, rename regression
  installer_validation_test.sh  115 tests — error paths, wizard flags, MCP schema/enabled/disabled,
                            dev bundle config, subcommand routing, handler files
  discord_sanitizer_test.sh 34 tests — sanitizer pattern matching
  discord_setup_test.sh     20 tests — setup wizard, config read/write
  cds_test.sh               19 tests — date-stamped scratch dir launcher, openchad reference
  integration_test.sh       11 tests — end-to-end installer flow
  installer_robustness_test.sh  24 tests — scenario-driven robustness
  setup_zsh_test.sh         32 tests — zsh plugin setup, managed .zshrc block
  shell_profile_test.sh     33 tests — shell profile PATH wiring, completions
  oc_sessions_test.sh       33 tests — oc-list, oc-killall, rename regression
  vision_test.sh            49 tests — Vision daemon setup, singleton startup, port health,
                            doctor checks, wizard/update/uninstall wiring, idempotency,
                            security (0600 perms), AGENTS.md documentation

docs/
  STATUS_BAR_IMPLEMENTATION.md   Implementation examples for status bar data sources
  STATUS_BAR_SOURCES.md          Available data sources and priority matrix
```

---

## Color Palette (ayu-dark)

All UI elements use the ayu-dark palette. Use these exact hex values:

Primary agent color constants are canonicalized in `lib/agent_palette.sh`:

| Agent | Hex |
|-------|-----|
| `build` | `#59C2FF` |
| `plan` | `#FFB454` |
| `scout` | `#F07178` |
| `refine` | `#AAD94C` |

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
  ├─ reads ~/.config/opencode/open-chad.json → providers array
  ├─ writes $OPEN_CHAD_CACHE_DIR/active_providers (label + cache_key per line)
  ├─ Z.ai API → $OPEN_CHAD_CACHE_DIR/zai (integer 0-100)
  ├─ GitHub Copilot API → $OPEN_CHAD_CACHE_DIR/copilot
  ├─ Anthropic API → $OPEN_CHAD_CACHE_DIR/claude
  └─ OpenAI API → $OPEN_CHAD_CACHE_DIR/codex

status_right.sh (called by tmux every 5s)
  ├─ reads $OPEN_CHAD_CACHE_DIR/active_providers for provider list/order
  └─ reads per-provider cache files → tmux format string with color thresholds
```

### Session Title Correlation

```
bin/openchad creates tmux session: "oc-<epoch_seconds>-<pid>"

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
bin/openchad (on launch, fire-and-forget)
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

### Vision MCP Daemon

```
wizard.sh / install.sh (Step 5 — setup_vision.sh)
  ├─ verifies vision binary on PATH (non-fatal warn if missing)
  ├─ creates ~/.config/vision/servers.yaml (0600) with 4 MCP servers:
  │     context7  → localhost:6276
  │     grep-app  → localhost:6288
  │     lgrep     → localhost:6285
  │     firecrawl → localhost:6281
  └─ reloads running daemon (vision daemon reload)

bin/openchad (on launch, fire-and-forget, singleton)
  ├─ atomic mkdir vision-start.lock (prevents duplicate starts)
  ├─ creates $OPEN_CHAD_CACHE_DIR/vision.log (0600) for daemon stderr
  ├─ nohup vision daemon start >> vision.log 2>&1 &
  └─ removes vision-start.lock after 2s delay

lib/update.sh (on openchad update)
  ├─ vision daemon stop (graceful, non-fatal)
  ├─ setup_vision.sh (idempotent re-registration)
  └─ daemon restarts immediately in update flow

openchad doctor (Section 5 — Vision daemon)
  ├─ checks vision binary on PATH
  ├─ vision daemon status
  └─ curl --max-time 2 health checks on all 4 MCP ports
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
| `metrics-start.lock` | Atomic mkdir startup lock | `bin/openchad` | `bin/openchad` (prevents duplicate collector starts) |
| `active_providers` | `Label cache_key` per line | `collect_metrics.sh` | `status_right.sh` (dynamic gauge rendering) |
| `zai` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `copilot` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `claude` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `codex` | Integer 0-100 or empty | `collect_metrics.sh` | `status_right.sh` |
| `vision.log` | Vision daemon stderr output | `bin/openchad` | Debugging (0600, owner-only) |

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
| `install_test.sh` | 131 | Idempotency, flags, file creation, MCP regression, openchad/oc manifest |
| `llm_fuel_test.sh` | 72 | Gauge rendering, API parsing, toggle, dynamic providers, active_providers robustness |
| `animation_test.sh` | 39 | Centering math, palette, phases, regression guards |
| `session_title_test.sh` | 31 | SQLite correlation, no-fallback, filtering, format |
| `installer_validation_test.sh` | 115 | Error paths, wizard flags, MCP schema/enabled/disabled, bundle config, subcommand routing |
| `discord_sanitizer_test.sh` | 34 | Sanitizer pattern matching |
| `discord_setup_test.sh` | 20 | Setup wizard, config read/write |
| `cds_test.sh` | 19 | Date-stamped scratch dir launcher, openchad reference |
| `integration_test.sh` | 11 | End-to-end installer flow |
| `installer_robustness_test.sh` | 24 | Scenario-driven robustness |
| `setup_zsh_test.sh` | 32 | Zsh plugin setup, managed .zshrc block |
| `shell_profile_test.sh` | 33 | Shell profile PATH wiring, completions |
| `oc_sessions_test.sh` | 33 | oc-list, oc-killall, rename regression |
| `vision_test.sh` | 49 | Vision daemon setup, singleton startup, port health, doctor checks, wizard/update/uninstall wiring, security |
| **Total** | **643** | |

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

Each `openchad` invocation creates a unique tmux session: `oc-<epoch_seconds>-<pid>`. If one OpenCode instance crashes, others are unaffected. The epoch is embedded in the session name to enable timestamp-based correlation with the OpenCode SQLite DB.

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
| CVE-001 | `bin/openchad`, `lib/discord/update.sh` | Discord lockfile moved from `/tmp` to `$OPEN_CHAD_CACHE_DIR` (user-private). Legacy `/tmp/discord-rpc.lock*` cleaned up on startup with symlink-safe deletion guards. |
| CVE-002 | `lib/setup_dev_bundle.sh` | Go tarball SHA256 verified before `sudo rm -rf /usr/local/go`. Requires `sha256sum`; aborts on mismatch or missing checksum file. |
| CVE-003 | `lib/setup_mcp.sh` | Removed silent `opencode.json` auto-wipe in `--yes` mode. Invalid JSON now exits with `ERROR:` + recovery instructions. See [Recovering from opencode.json conflicts](#recovering-from-opencodejson-conflicts). |
| CVE-004 | `lib/setup_opencode.sh` | Symlink sources rejected during agent/instruction/theme file copy. Symlinks are skipped with a `WARN:` message. |
| CVE-005 | `bin/openchad` | Discord `update.sh` stderr now logged to `$OPEN_CHAD_CACHE_DIR/discord.log` (0600) instead of `/dev/null`. |
| ISSUE-006 | `install.sh`, `lib/update.sh` | Symlink creation changed to atomic `ln -sfn`. Source existence validated before linking. |
| ISSUE-008 | `lib/wizard.sh` | Install log created with `install -m 0600` for atomic secure creation. |
| ISSUE-009 | `lib/setup_mcp.sh` | Node.js invocations use `process.argv` file inputs (not interpolated strings) for path safety. |
| ISSUE-010 | `bin/openchad` | Metrics collector singleton guard changed from `pgrep -f` to atomic `mkdir` lockdir (`metrics-start.lock`). Renamed from `metrics.lock` to avoid collision with the collector's own PID lockfile. Lockdir removed after 2s delay to close the race window. |
| ISSUE-011 | `lib/setup_dev_bundle.sh` | Go fallback version updated to `go1.26.0` with maintenance comment. |
| ISSUE-012 | `lib/check_environment.sh` | Non-fatal `python3` presence check added with `apt install python3` hint. |
| ISSUE-013 | `lib/setup_dev_bundle.sh` | `_persist_bundles` moved to after failure checks — failed installs no longer persist as selected. |
| ISSUE-016 | `lib/json_merge.sh` | 1MB size guard added before Node.js parse for both target file and merge payload. |
| ISSUE-017 | `lib/wizard.sh` | WSL detected via `/proc/version`; generates `~/open-chad-keybindings.ps1` instead of manual instructions. |
| ISSUE-018 | `lib/setup_shell_profile.sh` | Exports PATH directly after writing block for immediate availability. Does NOT source the user's rc file (security: avoids executing arbitrary user shell code in installer context). |
| ISSUE-019 | `lib/collect_metrics.sh` | `find` cleanup wrapped in `timeout 5` to prevent hangs on slow filesystems. |
| ISSUE-021 | `lib/setup_shell_profile.sh` | Heredoc changed from `<<'EOF'` to `<<EOF` with `\$HOME` for explicit intent. |

### Vision bundling (v1.3)

The following changes were applied to bundle Vision as a managed component:

| ID | Script | Fix |
|----|--------|-----|
| VISION-001 | `lib/setup_vision.sh` | New. Idempotent Vision server registration — creates `~/.config/vision/servers.yaml` (0600) with 4 MCP servers, reloads daemon. Non-fatal if vision binary missing. |
| VISION-002 | `bin/openchad` | Vision singleton daemon start added after metrics collector. Two-tier locking (`vision-start.lock` atomic mkdir). `vision.log` created with `install -m 0600`. Fire-and-forget. |
| VISION-003 | `lib/wizard.sh` | `setup_vision.sh` wired as Step 5 (after MCP, before Plugins). `TOTAL_STEPS` incremented 9→10. |
| VISION-004 | `lib/update.sh` | Vision stop→setup→restart block added after MCP setup. Daemon restarts immediately in update flow. |
| VISION-005 | `lib/openchad_doctor.sh` | Section 5 "Vision daemon" added: binary check, `vision daemon status`, 4-port health checks with `curl --max-time 2`. |
| VISION-006 | `lib/openchad_uninstall.sh` | `vision daemon stop` added to uninstall path (non-fatal). |

### Rename migration (v1.2)

The following migration fixes were applied in the v1.2 rename pass:

| ID | Script | Fix |
|----|--------|-----|
| RENAME-001 | `bin/openchad` | Renamed from `bin/open-chad`. Thin dispatcher routes subcommands via `case` statement to dedicated handler scripts. |
| RENAME-002 | `bin/oc` | New short alias. Forwards all args to openchad; adds `oc attach` and `oc switch` session helpers. |
| RENAME-003 | `lib/setup_shell_profile.sh` | Adds `~/dev/open-chad/bin` directly to PATH in shell rc files. No symlink management. |
| RENAME-004 | `install.sh`, `lib/update.sh` | Auto-removes stale `alias oc='open-chad'` and `export PATH=.../open-chad/bin` from `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`. |
| RENAME-005 | `lib/openchad_doctor.sh` | Detects stale `oc` alias in shell rc files and warns with remediation instructions. |
| RENAME-006 | `lib/collect_metrics.sh`, `lib/status_right.sh` | Dynamic provider configuration. Collector reads `providers` array from `open-chad.json`, writes `active_providers` cache. Renderer reads cache for dynamic gauge rendering. |

### Behavioral changes in `--yes` mode

- **CVE-003**: `setup_mcp.sh` no longer silently wipes `opencode.json` on parse failure. It exits with an error and recovery instructions. This is a **breaking change** for automated installs with corrupted configs — fix the config first.

### New environment requirements

- **python3**: `check_environment.sh` now warns (non-fatal) if `python3` is missing. Required for `session_title.sh` SQLite lookup. Install with: `sudo apt install python3`

---

## Installer Reference

> Moved from README.md — this is the single source of truth for installer internals.
> User-facing install instructions remain in [README.md](README.md).

### Prerequisites

| Tool | Required | Notes |
|------|----------|-------|
| `bash` | Yes | 4.0+ |
| `git` | Yes | Cloning and update command |
| `tmux` | Yes | 3.2+ recommended |
| `node` / `npm` | Yes | For JSON config merging |
| `pnpm` | Auto-installed | Via npm if missing |
| `opencode` | Yes | Install from https://opencode.ai |
| `jq` | Optional | Used by metrics collector; not required by render path |
| Ubuntu/Debian | Yes | Linux only; `/proc` metrics; apt bootstrapping |

### What gets installed

| Component | Path | Notes |
|-----------|------|-------|
| Launcher | `~/.local/bin/openchad` | Symlink (canonical name) |
| Short alias | `~/.local/bin/oc` | Resolves `oc <name>` to `~/dev/<name>`, forwards to openchad |
| Scratch launcher | `~/.local/bin/cds` | Symlink — creates `~/scratch/<date>` and launches openchad |
| Session lister | `~/.local/bin/oc-list` | Lists active oc-* tmux sessions |
| Session killer | `~/.local/bin/oc-killall` | Kills all oc-* tmux sessions |
| tmux theme | `~/.tmux.conf` (sourced) | ayu-dark, 2-row |
| ADV plugin | `~/dev/oc-plugins/advance/` | Spec-driven dev (pinned @ SHA from adv-lock.json) |
| ADV lock | `config/opencode/adv-lock.json` | Pinned commit SHA for ADV install |
| ADV commands (bundled) | `config/opencode/command/adv-*.md` | Offline fallback command docs |
| morph plugin | `~/dev/oc-plugins/morph-fast-apply/` | Fast-apply edits |
| Agents | `~/.config/opencode/agents/` | build, general, plan, scout, refine, librarian, explore, adv-researcher |
| Instructions | `~/.config/opencode/instructions/` | identity, rules, shell_strategy, mcp-tools, worktree-guide, lbp, post_install_verification |
| Commands | `~/.config/opencode/command/adv-*.md` | ADV slash commands |
| Theme | `~/.config/opencode/themes/ayu-dark.json` | ayu-dark color theme |
| opencode.json | `~/.config/opencode/opencode.json` | Plugin paths, MCP servers, instructions (additive merge) |
| Install state | `~/.config/opencode/open-chad.json` | Selected bundles, timestamps |
| Install log | `~/.config/opencode/open-chad-install.log` | Timestamped wizard log |

### Non-interactive / CI flags

```bash
# Skip specific wizard steps
bash install.sh --yes --skip-deps --skip-auth --skip-bundles
bash install.sh --yes --skip-mcp --skip-adv --skip-morph
bash install.sh --yes --skip-omp --skip-zsh

# Select bundles non-interactively (comma or space separated, both work)
bash install.sh --yes --bundles python,go
bash install.sh --yes --bundles "python go rust web"

# Skip environment pre-flight check
bash install.sh --yes --no-env-check

# Legacy opt-out flags (still supported)
bash install.sh --no-adv
bash install.sh --no-omp
bash install.sh --no-opencode-setup

# Skip everything new (tmux + symlink only)
bash install.sh --no-adv --no-omp --no-opencode-setup
```

### Shell support (bash + zsh)

The installer automatically detects your active shell (`$SHELL`) and writes an idempotent `~/.local/bin` PATH export to the correct rc file:

| Shell | Target file |
|-------|-------------|
| `bash` | `~/.bashrc` |
| `zsh` | `~/.zshrc` |
| other / unknown | `~/.profile` |

The block is guarded by `# BEGIN open-chad` / `# END open-chad` markers — re-running the installer never duplicates it.

Shell completions for `openchad` and `oc` are also wired automatically:
- **bash**: `completion/openchad.bash` is sourced in `~/.bashrc`
- **zsh**: `completion/_openchad.zsh` is added to `fpath` in `~/.zshrc`

### Recovering from opencode.json conflicts

If `setup_mcp.sh` exits with an error about invalid or unparseable `opencode.json`, it will **not** automatically overwrite your config. This is intentional — silent auto-recovery was removed (CVE-003) to prevent data loss.

**Option A — Restore from git backup (recommended):**
```bash
git checkout ~/.config/opencode/opencode.json
```

**Option B — Manual config merge:**
```bash
node -e "JSON.parse(require('fs').readFileSync('~/.config/opencode/opencode.json','utf8'))"
# Fix any syntax errors shown, then re-run:
bash install.sh
```

**Option C — Clean reinstall (last resort):**
```bash
cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak
rm ~/.config/opencode/opencode.json
bash install.sh
```

### Windows Terminal (WSL)

The wizard (step 9) offers optional keybinding setup for Shift+Enter and Ctrl+Backspace in WSL. On WSL, it generates `~/open-chad-keybindings.ps1` — copy it to your Windows home and run in PowerShell:

```powershell
cp ~/open-chad-keybindings.ps1 /mnt/c/Users/$USER/
# Then in PowerShell:
.\open-chad-keybindings.ps1
```

On non-WSL systems, the wizard displays the JSON to add manually to your Windows Terminal `settings.json`.

### Provider gauge customization

By default, all 4 providers are shown. Customize which providers appear by adding a `providers` array to `~/.config/opencode/open-chad.json`:

```json
{
  "providers": ["zai", "claude"]
}
```

Valid provider IDs: `zai`, `copilot`, `claude`, `codex`. The gauge renders only the providers you specify, in the order you specify them.

### `OPEN_CHAD_MULTI_GAUGE` toggle

Controls whether the per-provider fuel gauge is shown in the status bar.

| Value | Behavior |
|-------|----------|
| unset / `auto` | Show gauge only if at least one provider cache file has valid data (default) |
| `1` / `true` / `yes` / `on` | Always show gauge (all segments, unknown providers show `--`) |
| `0` / `false` / `no` / `off` | Never show gauge |

Set in your shell profile or `~/.tmux.conf`:

```bash
export OPEN_CHAD_MULTI_GAUGE=1   # Always show
export OPEN_CHAD_MULTI_GAUGE=0   # Never show
```

The toggle affects both `collect_metrics.sh` (skips API calls when disabled) and `status_right.sh` (hides the segment when disabled).

### ADV bundling modes

ADV is installed at a pinned commit SHA by default. The lock file `config/opencode/adv-lock.json` contains the repo URL and pinned ref.

| Mode | Env var | Behavior |
|------|---------|----------|
| `pinned` (default) | `ADV_INSTALL_MODE=pinned` | Checkout at SHA from `adv-lock.json` |
| `latest` | `ADV_INSTALL_MODE=latest` | Pull latest HEAD (ignores lock ref) |
| `offline` | `ADV_INSTALL_MODE=offline` | Skip network; sync bundled docs only |

**Two-tier fallback only:** network clone/build → bundled `config/opencode/command/adv-*.md`. No third tier.

**Lock bump workflow** (update pinned SHA to latest):
```bash
openchad update --adv-latest
# This pulls latest ADV and updates adv-lock.json ref to the new HEAD SHA
```

**Lock file format** (`config/opencode/adv-lock.json`):
```json
{
  "repo": "https://github.com/Sharper-Flow/Advance.git",
  "ref": "<40-char-hex-commit-sha>",
  "pluginPath": "plugin"
}
```

The `ref` field must be a 40-character lowercase hex commit SHA. Branch names and semver tags are rejected — the installer falls back to bundled docs with a WARN.

---

## Known Limitations

- **OpenCode TUI logo is not patchable** — the logo is dynamically generated at runtime inside a compiled Bun binary. No static string to replace. An upstream PR (#12017) for custom logo config exists but hasn't merged as of v1.2.10.
- **LLM quota APIs are undocumented** — endpoints were reverse-engineered from browser/editor traffic. They may change without notice.
- **Copilot percent_remaining can be negative** — when over quota. The collector clamps to 0.
- **Session title requires python3** — the SQLite query uses python3 for parameterized queries. This is the only script with a python3 dependency.
- **Linux-only for /proc metrics** — `collect_metrics.sh` reads `/proc/stat`, `/proc/meminfo`, `/proc/loadavg`. macOS would need different implementations.
