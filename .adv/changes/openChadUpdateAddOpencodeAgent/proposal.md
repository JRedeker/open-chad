# open-chad-update: OpenCode agent/sub-agent setup, ADV + omp install from GitHub, global instruction file sync

## Why

`open-chad` currently installs only the tmux launcher and retro theme. Users who adopt it still have to manually wire up:
- the ADV spec-driven development plugin
- the `omp` (opencode-model-preferences) model-routing TUI
- shared agent and sub-agent markdown files (`scout`, `refine`, `librarian`, `adv-researcher`, `explore`)
- global instruction files that apply to every project (`shell_strategy`, `mcp-tools`, `worktree-guide`, `lbp`)
- ADV slash commands (`adv-*`) in the OpenCode command directory

This change makes `open-chad` the single install step for a fully configured OpenCode developer environment.

## What Changes

### New files in `open-chad`

- `config/opencode/agents/` — bundled copies of all agent markdown files (scout, refine, librarian, explore)
- `config/opencode/instructions/` — bundled copies of global instruction files (shell_strategy, mcp-tools, worktree-guide, lbp)
- `lib/setup_opencode.sh` — idempotent OpenCode environment setup script (agents, commands, instructions sync)
- `lib/setup_adv.sh` — installs/updates ADV from GitHub, builds plugin, wires into `opencode.json`
- `lib/setup_omp.sh` — installs/updates `omp` from GitHub (builds Go binary to `~/.local/bin/`)
- `lib/json_merge.sh` — helper for safe JSON key merging without clobbering existing config

### Modified files

- `install.sh` — calls OpenCode setup steps after existing tmux steps (with opt-out flags)
- `README.md` — documents new setup behavior, opt-out flags, and what gets installed

### Generated / synced at install time

- `~/.config/opencode/agents/*.md` — agent files synced from bundle
- `~/.config/opencode/command/adv-*.md` — ADV commands synced from advance plugin checkout
- `~/.config/opencode/instructions/*.md` — global instructions synced from bundle
- `~/.config/opencode/opencode.json` — `plugin` and `instructions` keys merged idempotently
- `~/dev/oc-plugins/advance/` — ADV cloned/updated from `https://github.com/Sharper-Flow/Advance.git`
- `~/dev/oc-plugins/opencode-model-preferences/` — omp cloned/updated from `https://github.com/anomalyco/opencode-model-preferences.git`
- `~/.local/bin/omp` — built and symlinked

## Success Criteria

- [ ] `install.sh` completes without error on a clean machine with only `bash`, `git`, `go`, `node`/`pnpm`, and `tmux` available
- [ ] After install, `~/.config/opencode/agents/` contains all bundled agent markdown files
- [ ] After install, `~/.config/opencode/command/` contains all `adv-*.md` commands from the ADV checkout
- [ ] After install, `~/.config/opencode/opencode.json` plugin entry for ADV is present and points to the correct checkout path
- [ ] After install, `~/.config/opencode/opencode.json` instructions array includes all global instruction file paths
- [ ] After install, `omp` binary exists at `~/.local/bin/omp` and is executable
- [ ] Running `install.sh` a second time (re-run) is fully idempotent — no duplicate entries, no errors
- [ ] `--no-adv` flag skips ADV install and plugin wiring
- [ ] `--no-omp` flag skips omp build/install
- [ ] `--no-opencode-setup` flag skips all OpenCode config changes
- [ ] If `go` is not available, omp install is skipped with a clear message; overall install still succeeds (exit 0)
- [ ] If `pnpm` is not available for ADV build, a clear install instruction is printed and ADV step is skipped gracefully

## Affected Code

- `install.sh` — add OpenCode setup phase invocations and flag parsing
- `lib/setup_opencode.sh` (new) — agent/command/instruction sync, `opencode.json` merge
- `lib/setup_adv.sh` (new) — git clone/pull of Advance, `pnpm install && pnpm build` in plugin dir
- `lib/setup_omp.sh` (new) — git clone/pull of opencode-model-preferences, `make install`
- `lib/json_merge.sh` (new) — JSON path merge helper (prefers `jq`; falls back to `node -e`)
- `config/opencode/agents/*.md` (new directory) — bundled agent files (scout, refine, librarian, explore)
- `config/opencode/instructions/*.md` (new directory) — bundled instruction files
- `README.md` — document new setup behavior, opt-out flags, and prerequisites

## Constraints

- MUST: all config mutations are idempotent (safe to re-run without side effects)
- MUST: no existing `opencode.json` keys are deleted or overwritten — only additive merges
- MUST: work in bash without external tools beyond `git`, `go`, `node`/`pnpm`, and optionally `jq`
- MUST NOT: bundle personal identity/provider/model config — those stay user-managed
- SHOULD: install ADV commands by reading them from the ADV checkout (not hardcoded copies) so they stay in sync with upstream
- SHOULD: emit a clear per-step summary with colored output consistent with existing `install.sh` style

## Impact

- New feature — no breaking changes to existing `install.sh` behavior
- All new OpenCode steps are opt-out via flags; existing users who re-run install get the new steps
- Adds optional dependencies: `go` (for omp), `pnpm` (for ADV build), `jq` (for JSON merge; has fallback)

## Risks

- `jq` not universally available → mitigated by `node -e` JSON fallback
- ADV or omp GitHub repo URL changes → mitigated by `ADVANCE_REPO` / `OMP_REPO` env var overrides in setup scripts
- `pnpm` absent → script prints instructions; ADV plugin wiring skipped gracefully

## Research Validation

_Completed: 2026-02-23 — 5 parallel sub-agents_

### R1: Testing Framework — SIMPLIFICATION OPPORTUNITY
**Current plan:** bats  
**Finding:** OVER-ENGINEERED. bats adds tool overhead for straightforward installer testing.  
**Recommendation:** Use plain bash test scripts (`tests/install_test.sh`) with simple assert helper functions. No framework needed for this test surface.  
**Impact:** Simpler CI setup, no additional dependency, same coverage.

### R2: JSON Merge Strategy — SIMPLIFICATION OPPORTUNITY
**Current plan:** jq primary + node -e fallback (two code paths)  
**Finding:** Node is already a required dependency (pnpm/npm). Maintaining two implementations adds unnecessary complexity.  
**Recommendation:** Node.js only — single ~20-line `idempotentMerge` function. One code path, testable, no jq needed.  
**Impact:** Remove `jq` as mentioned tool; `lib/json_merge.sh` becomes a thin node wrapper or inline node script.

### R3: pnpm Plugin Build — VALIDATED (with caveats)
**Current plan:** git clone/pull + `pnpm install` + `pnpm build`  
**Finding:** VALIDATED. Do NOT use `--frozen-lockfile` for fresh checkouts (causes failures if lockfile absent or pnpm version mismatch). Plain `pnpm install` is correct. The plugin path in opencode.json references source root (`plugin/`), not `dist/`.  
**Recommendation:** Keep approach. Add `npm` as fallback if pnpm absent rather than silently skipping.

### R4: Go Binary Install — ANTI-PATTERN DETECTED
**Current plan:** git clone + `make install`  
**Finding:** ANTI-PATTERN vs 2025 best practice. `go install github.com/anomalyco/opencode-model-preferences@latest` is the official Go team recommendation since Go 1.16. Eliminates all checkout management (~30 lines → 3 lines), natively idempotent, version-pinnable.  
**Recommendation:** Replace `lib/setup_omp.sh` implementation with `GOBIN=~/.local/bin go install ...@${OMP_VERSION:-latest}`. The checkout-based approach in the task description should be revised.

### R5: Bash Installer Patterns — VALIDATED (with correction)
**Current plan:** Flag parsing for --no-adv, --no-omp, --no-opencode-setup; sourced lib scripts  
**Finding:** VALIDATED overall. One correction: `getopts` (bash builtin) does NOT support long flags. Use GNU `getopt` or a simple manual `while [[ $# -gt 0 ]]; do case` loop (simpler for 3 flags).  
**Recommendation:** Use manual case loop for flag parsing (no external dependency). Source `lib/setup_*.sh` from `install.sh` (not execute as subshell). Keep single orchestrator pattern.

### Action Items from Research
- [ ] (R1) Replace bats with plain bash test scripts in `tests/`
- [ ] (R2) Implement `lib/json_merge.sh` as Node-only (no jq path)
- [ ] (R4) Rewrite `lib/setup_omp.sh` to use `go install` instead of git clone + make install
- [ ] (R5) Flag parsing: use manual `while/case` loop in `install.sh` (not getopts)
- [ ] (R3) Confirm pnpm install uses no `--frozen-lockfile` flag

## Validation Plan

- Write a `bats` (bash automated testing system) test suite in `tests/` covering:
  - idempotency: re-running install produces no duplicates and no errors
  - flag behavior: `--no-adv`, `--no-omp`, `--no-opencode-setup` correctly skip their steps
  - file creation: each setup script creates/syncs expected files
  - missing deps: graceful skip + warning when `go` or `pnpm` absent
- Red phase: write failing tests before implementing setup scripts
- Green phase: implement scripts to pass tests
- Manually verify on a clean PATH-isolated environment after tests pass
