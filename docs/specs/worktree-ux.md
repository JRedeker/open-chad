# Worktree Ux

> **Version:** 2.0.0
> **Updated:** 2026-03-17

## Purpose

Capability: Worktree Ux

## Requirements

### Worktree creation defaults to inline mode

**ID:** `rq-wt-ux.1` | **Priority:** **[MUST]**

When the worktree plugin creates a git worktree via `worktree_create`, it must default to inline mode: no new terminal or tmux window is opened. The agent continues in the same session, using the returned worktree path as `workdir` for all subsequent tool calls. Projects can opt out by setting `"inline": false` in `.opencode/worktree.jsonc`.

#### Scenarios

**Inline worktree creation returns path for workdir usage** (`sc-wt-ux.1.1`)

**Given:**
- An ADV change is active
- The worktree plugin has `inline: true` (default)
- The agent calls `worktree_create` and it succeeds

**When:** The agent continues with implementation

**Then:**
- No new terminal window or tmux window is opened
- The tool returns the worktree path
- The agent uses the returned path as `workdir` for all subsequent tool calls
- The agent does not emit tmux navigation hints

**Inline mode documentation is consistent across all sources** (`sc-wt-ux.1.2`)

**Given:**
- adv-apply.md in the ADV repo contains the worktree creation protocol
- ADV_INSTRUCTIONS.md in the ADV repo contains the inline worktree protocol
- skills/worktree/SKILL.md in openchad contains the inline mode section
- README.md in openchad contains the Worktree Flow section

**When:** The inline mode guidance is compared across all four sources

**Then:**
- All sources describe inline mode as the default behavior
- All sources instruct the agent to use the returned path as `workdir`
- No source references tmux navigation hints as part of the default flow

---

### Worktree inline mode is documented in openchad user-facing docs

**ID:** `rq-wt-ux.2` | **Priority:** **[MUST]**

openchad must document worktree inline mode behavior in both the worktree skill (skills/worktree/SKILL.md) and the user-facing README.

#### Scenarios

**worktree skill contains Inline Mode section** (`sc-wt-ux.2.1`)

**Given:**
- config/opencode/skills/worktree/SKILL.md exists in the openchad repo

**When:** The file is read

**Then:**
- A section titled 'Inline Mode (Default)' is present
- The section describes that no new terminal is opened
- The section instructs using the returned path as `workdir`

**README.md contains Worktree Flow section** (`sc-wt-ux.2.2`)

**Given:**
- README.md exists in the openchad repo

**When:** The file is read

**Then:**
- A section titled 'Worktree Flow' is present
- The section describes inline mode as the default behavior

---
