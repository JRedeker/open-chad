# Changelog

All notable changes to this project are documented in this file.

## [v1.3.0] — 2026-03-05

### Added

- **Agent-driven installer** (`/open-chad-install`): new slash command for users who already have OpenCode and want to install open-chad from within an agent session. Runs all 10 setup steps and a full verification checklist.
- **External Dependencies table** in README: formatted table of all 14 external repos, plugins, MCP servers, and packages with correct source links and install methods.
- **Vision MCP daemon bundling** (v1.3): singleton daemon auto-started on every `openchad` launch, restarted on `openchad update`, health-checked by `openchad doctor`. Manages Context7, grep.app, lgrep, and Firecrawl MCP servers.
- **lgrep v2 support**: updated Vision config to use `uvx` runner, bundled `SKILL.md` with semantic + symbol search guidance, `.lgrepignore` scaffolding via `lgrep init-ignore`.
- **Post-install verification prompt**: wizard now always shows the 8-point verification checklist (both interactive and `--yes` mode) so users know exactly what to paste into OpenCode after install.
- **Atomic JSON merge safety** (`json_merge.sh`): `--backup` flag creates `.bak.<epoch>` with 0600 perms before merge; `--rotate <N>` keeps only N most-recent backups; atomic write via `fs.renameSync`.
- **On-demand skills**: `mcp-selection` and `worktree` instructions converted from always-loaded to skill files loaded via the skill tool.
- **P26 rule** (`question-tool-write-in`): every use of the question/ask tool must include an explicit write-in option.
- **Session count** in status bar metrics.

### Changed

- **ADV always-latest mode**: removed `adv-lock.json` and SHA pinning entirely. ADV always pulls latest HEAD from `github.com/Sharper-Flow/Advance`. Only two modes remain: `latest` (default) and `offline`. Removed `--adv-latest` flag from `openchad update`.
- **omp installer rewritten**: switched from `go install` to git clone + `make install` pattern using correct repo (`github.com/JRedeker/opencode-model-preferences`).
- **morph repo URL fixed**: `github.com/anomalyco/morph-fast-apply` → `github.com/JRedeker/opencode-morph-fast-apply`.
- **openchad doctor**: removed lock file validation section; replaced with always-latest confirmation.
- **`setup_opencode.sh`**: now syncs `open-chad-*.md` commands alongside ADV commands.

### Fixed

- **getcwd errors on `/exit`**: all 7 tmux status bar shell invocations (`session_title.sh`, `status_left.sh`, `status_right.sh`, `status_edges.sh`, `status_resources.sh`, `theme.conf` pane-border-format) now `cd "$HOME"` before any work and bail early if the pane's cwd no longer exists. `bin/openchad` saves the session cwd and restores it before `exec tmux attach` so the parent terminal has a valid cwd after exit.
- **Integration test**: `test_update_error_message_content` now copies `update.sh` into the fake non-git directory so `SCRIPT_DIR` resolves correctly (was always passing due to real repo's `.git` being found).
- **Wizard timeout in tests**: added `--skip-omp --skip-zsh` to the `--yes` mode test to prevent hanging on network-dependent steps.

### Removed

- `config/opencode/adv-lock.json` — no longer needed (always-latest mode).
- `--adv-latest` flag from `openchad update` and `lib/update.sh`.
- Lock file validation from `openchad doctor`.
- All `ADV_INSTALL_MODE=pinned` references.

## [v1.2.0] — 2025-12-15

Internal release (never tagged). Changes folded into v1.3.0.

## [v1.1.0]

- PATH-based installation (replaced symlinks)
- Security hardening pass (CVE-001 through CVE-005, ISSUE-006 through ISSUE-022)
- Rename migration (`open-chad` → `openchad`)
- Dynamic LLM provider gauges
- Discord Rich Presence with WSL2 bridge
- omp model-preferences TUI popup
- Synthwave status edges

<!-- OPENCHAD_RELEASE_NOTES -->
