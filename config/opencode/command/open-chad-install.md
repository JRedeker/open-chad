---
name: open-chad-install
description: Install open-chad into an existing OpenCode setup (agent-driven)
agent: build
---

# open-chad Install (Agent-Driven)

Install open-chad components into an existing OpenCode environment. This command is for users who already have OpenCode running and want to add open-chad's context engineering stack on top.

## Prerequisites

Before running this command, the user must have:
1. OpenCode installed and working
2. The open-chad repo cloned: `git clone https://github.com/JRedeker/open-chad.git ~/dev/open-chad`
3. This session launched from the open-chad repo directory

## Execution

Run each step sequentially. Report progress after each step. If a step fails, report the error and continue to the next step (all steps are non-fatal).

### Step 1: Verify Environment

```bash
# Confirm we're in the open-chad repo
[ -f ./install.sh ] && [ -f ./lib/wizard.sh ] && echo "OK: open-chad repo" || echo "FAIL: not in open-chad repo"

# Check required tools
for cmd in git node npm tmux; do
  command -v "$cmd" &>/dev/null && echo "OK: $cmd" || echo "FAIL: $cmd not found"
done
```

### Step 2: Shell PATH Setup

```bash
bash lib/setup_shell_profile.sh
```

This adds `~/dev/open-chad/bin` to PATH in the user's shell rc file. Idempotent.

### Step 3: tmux Theme

Check if `~/.tmux.conf` already sources the open-chad theme. If not, append the source line:

```bash
# Check if already wired
if grep -q 'open-chad' ~/.tmux.conf 2>/dev/null; then
  echo "OK: tmux theme already wired"
else
  echo "" >> ~/.tmux.conf
  echo "# open-chad tmux theme" >> ~/.tmux.conf
  echo "source-file ~/dev/open-chad/lib/theme.conf" >> ~/.tmux.conf
  echo "OK: tmux theme wired"
fi
```

### Step 4: MCP Servers

```bash
bash lib/setup_mcp.sh
```

Wires Context7, grep.app, lgrep, and Firecrawl into `~/.config/opencode/opencode.json`. Idempotent — uses additive JSON merge.

### Step 5: Vision MCP Daemon

```bash
bash lib/setup_vision.sh
```

Registers MCP servers in `~/.config/vision/servers.yaml` and reloads the daemon. Non-fatal if the `vision` binary is not on PATH.

### Step 6: ADV Plugin

```bash
bash lib/setup_adv.sh
```

Clones/updates the ADV spec-driven development plugin to `~/dev/oc-plugins/advance/`. Always pulls latest HEAD. Falls back to bundled command docs on network failure.

### Step 7: morph-fast-apply Plugin

```bash
bash lib/setup_morph.sh
```

Clones/updates morph-fast-apply to `~/dev/oc-plugins/morph-fast-apply/`. Syncs the morph skill to `~/.config/opencode/skills/morph/`.

### Step 8: Agents, Instructions, Theme, Commands

```bash
bash lib/setup_opencode.sh
```

Syncs all agents (build, plan, scout, refine, explore, librarian, general, adv-researcher), instruction files, the ayu-dark theme, skills, and slash commands into `~/.config/opencode/`. Wires the md-table-formatter plugin. Idempotent.

### Step 9: Model Preferences (omp)

```bash
bash lib/setup_omp.sh
```

Clones/builds the omp model-preferences TUI. Requires Go 1.16+. Non-fatal if Go is not installed.

### Step 10: Zsh Plugins (optional)

```bash
bash lib/setup_zsh_plugins.sh
```

Installs Powerlevel10k, zsh-autosuggestions, and fast-syntax-highlighting. Adds a managed block to `~/.zshrc`. Non-fatal.

## Post-Install Verification

After all steps complete, run through this verification checklist and report results:

1. **AUTH** — You can read this message (API auth is working). → OK
2. **ADV PLUGIN** — Run: `/adv-status`. Expected: a project overview table. If "unknown command", the ADV plugin is not loaded.
3. **LGREP MCP** — Run: `lgrep_search_semantic(q="hello world", path=".")`. Expected: search results or "no results" (not tool-not-found). Note: "VOYAGE_API_KEY not set" means wiring is OK but semantic search needs the key set in `~/.config/vision/servers.yaml` under `lgrep.env`.
4. **MORPH PLUGIN** — Confirm `morph_edit` tool appears in your tool list.
5. **THEME** — Confirm the ayu-dark color theme is active (dark background #0D1017, golden yellow accents).
6. **AGENTS** — Confirm these primary agents are available: build, plan, scout, refine. Other agents (general, explore, librarian, adv-researcher) should NOT appear in the primary agent picker.
7. **MD-TABLE-FORMATTER** — Check opencode.json plugin array contains `@franlol/opencode-md-table-formatter@latest`.
8. **SKILLS** — Check `~/.config/opencode/skills/` contains: `mcp-selection/SKILL.md`, `worktree/SKILL.md`, `lgrep/SKILL.md`, `morph/SKILL.md`.

### Report Format

```
open-chad Install Results
═════════════════════════
Step  1: Environment     — OK
Step  2: Shell PATH      — OK
Step  3: tmux Theme      — OK
Step  4: MCP Servers     — OK
Step  5: Vision Daemon   — OK / WARN (vision binary not on PATH)
Step  6: ADV Plugin      — OK
Step  7: morph Plugin    — OK
Step  8: Config Sync     — OK
Step  9: omp             — OK / SKIP (Go not installed)
Step 10: Zsh Plugins     — OK / SKIP

Verification
────────────
1. AUTH    — OK
2. ADV     — OK
3. MCP     — OK
4. MORPH   — OK
5. THEME   — OK
6. AGENTS  — OK
7. PLUGIN  — OK
8. SKILLS  — OK
```

If any verification item fails, include the fix command from the table below:

| Check | Fix Command |
|-------|-------------|
| ADV missing | `bash lib/setup_adv.sh` |
| lgrep missing | Check `~/.config/opencode/opencode.json` for lgrep MCP entry |
| morph missing | `bash lib/setup_morph.sh` |
| md-table-formatter missing | `bash lib/setup_opencode.sh` |
| Theme wrong | `bash lib/setup_opencode.sh` |
| Agents missing | `bash lib/setup_opencode.sh` |
| Skills missing | `bash lib/setup_opencode.sh` + `bash lib/setup_morph.sh` |
