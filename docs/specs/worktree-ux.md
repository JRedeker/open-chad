# Worktree Ux

> **Version:** 1.0.0
> **Updated:** 2026-02-26

## Purpose

Capability: Worktree Ux

## Requirements

### Agent emits tmux navigation hint immediately after worktree_create succeeds

**ID:** `rq-wt-ux.1` | **Priority:** **[MUST]**

When the ADV agent creates a git worktree via worktree_create, it must immediately emit a navigation hint block telling the user how to reach the new tmux window. The hint must include: Ctrl+b n (next window), Ctrl+b l (last window), Ctrl+b w (interactive chooser), and oc switch (session switcher). The hint must appear before the agent continues inline implementation.

#### Scenarios

**Navigation hint emitted after successful worktree_create** (`sc-wt-ux.1.1`)

**Given:**
- An ADV change is active
- The agent calls worktree_create and it succeeds
- A new tmux window may have opened for the worktree

**When:** The agent continues with implementation

**Then:**
- The agent emits a navigation hint block before any further tool calls
- The hint includes Ctrl+b n, Ctrl+b l, Ctrl+b w, and oc switch
- The hint states the worktree path and branch name
- The hint states that implementation continues inline via workdir

**Navigation hint wording is consistent across all sources** (`sc-wt-ux.1.2`)

**Given:**
- adv-apply.md in the ADV repo contains the navigation hint block
- ADV_INSTRUCTIONS.md in the ADV repo contains the navigation hint block
- worktree-guide.md in openchad contains the navigation hint section
- README.md in openchad contains the Worktree Flow section

**When:** The canonical keybinds are compared across all four sources

**Then:**
- All sources list the same four keybinds: Ctrl+b n, Ctrl+b l, Ctrl+b w, oc switch
- No source references the non-existent oc window command

---

### Worktree navigation guidance is documented in openchad user-facing docs

**ID:** `rq-wt-ux.2` | **Priority:** **[MUST]**

openchad must document worktree navigation keybinds in both the agent instruction file (worktree-guide.md) and the user-facing README. The AGENTS.md developer reference must also note the navigation hint section.

#### Scenarios

**worktree-guide.md contains Navigating to the New Worktree Tab section** (`sc-wt-ux.2.1`)

**Given:**
- config/opencode/instructions/worktree-guide.md exists in the openchad repo

**When:** The file is read

**Then:**
- A section titled 'Navigating to the New Worktree Tab' is present
- The section contains a keybind table with Ctrl+b n, Ctrl+b l, Ctrl+b w, and oc switch

**README.md contains Worktree Flow section** (`sc-wt-ux.2.2`)

**Given:**
- README.md exists in the openchad repo

**When:** The file is read

**Then:**
- A section titled 'Worktree Flow' is present
- The section contains the four navigation keybinds

---
