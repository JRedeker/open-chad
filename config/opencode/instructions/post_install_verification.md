# open-chad Post-Install Verification

After installing open-chad, paste the following prompt into OpenCode to confirm
every component is wired correctly. Each numbered item targets a specific
subsystem — a failure pinpoints exactly what needs attention.

---

## Verification Prompt (copy/paste into OpenCode)

```
Hello! I just installed open-chad. Please run through this checklist and
confirm each item works:

1. AUTH — You can read this message (Claude API auth is working).

2. ADV PLUGIN — Run: /adv-status
   Expected: a project overview table (specs, changes, recommendations).
   If you see "unknown command", the ADV plugin is not loaded.

3. LGREP MCP — Run this tool call:
   lgrep_search(q="hello world", path=".")
   Expected: search results or "no results" (not a tool-not-found error).
   If the tool is missing, the lgrep MCP server is not wired.

4. MORPH PLUGIN — Run: morph_edit on a trivial test (or confirm the tool
   appears in your tool list).
   Expected: morph_edit tool is available.
   If missing, the morph-fast-apply plugin is not installed.

5. THEME — Confirm the ayu-dark color theme is active.
   Expected: dark background (#0D1017), golden yellow accents.
   If the theme looks wrong, re-run: open-chad (setup_opencode.sh syncs theme).

6. AGENTS — Confirm these agents are available: scout, refine, librarian,
   explore, build, general, plan.
   Expected: all 7 agents listed when you check agent configuration.

Please report the status of each item (OK / FAIL + error message).
```

---

## Quick Reference: Fix Commands

| Check | Fix Command |
|-------|-------------|
| Auth fails | `open-chad` → re-run OAuth via `lib/setup_opencode_auth.sh` |
| ADV missing | `bash lib/setup_adv.sh` |
| lgrep missing | Check `~/.config/opencode/opencode.json` for lgrep MCP entry |
| morph missing | `bash lib/setup_morph.sh` |
| Theme wrong | `bash lib/setup_opencode.sh` |
| Agents missing | `bash lib/setup_opencode.sh` |

---

## Shell PATH Check

If `open-chad` is not found after install, your shell profile needs updating.
Run the appropriate command for your shell:

```bash
# bash
source ~/.bashrc

# zsh
source ~/.zshrc
```

If neither works, check that `~/.local/bin` is in your PATH:

```bash
echo $PATH | tr ':' '\n' | grep local
```

If missing, add to your shell profile:

```bash
export PATH="$HOME/.local/bin:$PATH"
```
