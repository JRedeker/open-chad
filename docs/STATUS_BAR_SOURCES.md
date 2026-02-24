# Status Bar Information Sources

## Current Left Side (title_parser.sh)
Displays: `▎ 🚀 ADV ▎ repo / changeId [extra]`

Parses from window name:
- Emoji → State (🚀=ADV, 🌍=WEB, 🎤=VOZ, 🌙=IDL, 💬=CHT, ⚙️=CFG)
- Repo name
- Change ID
- Optional extra context

## Current Right Side (status_right.sh)
Displays: `branch │ cpu XX% │ ram XX% │ ld XX ▐▐▐▐`

- Git branch with dirty flag (*)
- CPU % (1-second sample)
- RAM % (memory used)
- 1-minute load average

---

## High-Value Information Available for Left Side

### 1. Task Progress ⭐⭐⭐⭐⭐
**Source:** `~/.local/share/opencode/plugins/advance/{project-id}/changes/{changeId}/change.json`

- Current task ID and phase (🔴 red / 🟢 green / ⚪ none)
- Task count: completed/total (e.g., "5/9")
- Task status: pending/in_progress/blocked/completed/cancelled

**Why:** Immediate "what am I working on?" and "how stuck?" indicator

**Display:** `[tk-abc] 🟢 5/9` or `[tk-xyz] 🔴 0/10 (blocked)`

---

### 2. Worktree State ⭐⭐⭐⭐
**Source:** `~/.local/share/opencode/worktree/{project-id}/`

- Is worktree active? (yes/no)
- Worktree path if active
- Associated change ID
- Commits ahead of default branch

**Why:** Safety critical. Prevents accidental deletion of isolated work. Shows risky refactors in progress.

**Display:** `🌳 wt-change-123 ↑3` or `🌳 isolated`

---

### 3. Gate Progress ⭐⭐⭐
**Source:** `change.json` → deltas field

6-gate workflow: research → prep → implementation → review → harden → signoff

Each gate has completion status (pass/fail/pending)

**Why:** Shows where work is stuck. Is it waiting on review? Harden?

**Display:** `gates: ✓prep ✓impl ▶review ⊘harden`

---

### 4. Project Health (Aggregate) ⭐⭐⭐
**Source:** `~/.local/share/opencode/plugins/advance/{project-id}/changes/` directory

- Count of changes by status: draft, in_progress, reviewing, archived
- Archived but unmerged branches (risky)

**Why:** Project-level snapshot. Prevents lost work. Shows workflow congestion.

**Display:** `proj: 1▶ 0⊙ 2✓ (1 pending merge)`

---

### 5. File Changes ⭐⭐⭐
**Source:** Git (already used in pane)

- Number of unstaged files
- Number of staged files
- Stashed changes count
- Commits ahead/behind upstream

**Why:** Shows if ready to commit. Stash count reveals forgotten branches.

**Display:** `+3 ~2 -1 | 5 stashed | ↑2 commits`

---

### 6. Wisdom & Agenda ⭐⭐
**Source:** `wisdom.jsonl`, `agenda.jsonl` in external state

- Count of recorded project decisions
- Count of pending agenda items

**Why:** Shows captured knowledge and work queue depth.

**Display:** `wisdom:24 | agenda:7`

---

### 7. Specs Coverage ⭐⭐
**Source:** `.adv/specs/` and `db/spec.db`

- Spec count
- Implementation coverage (derived from change mappings)

**Why:** Spec-driven development indicator. Are you drifting?

**Display:** `specs: 18/21 ✓`

---

### 8. ADV Status Phase ⭐⭐
**Source:** Protocol marker (from agent output)

- ROCKET (🚀) = Active work
- RED (🔴) = Writing tests
- GREEN (🟢) = Implementing
- MOON (🌕) = Waiting for sub-agents
- EARTH (🌍) = Complete/awaiting input
- DOOM_LOOP (🔄) = Stuck retrying
- MIC (🎤) = Needs approval

**Why:** Immediately shows if agent is blocked or working.

**Display:** Emoji already in title, could enhance to show current phase

---

## Implementation Priority

| Priority | Info | Impact | Effort |
|----------|------|--------|--------|
| 🔴 1 | Task progress (phase + count) | "what am I doing?" | Low |
| 🔴 2 | Worktree alert | Safety (prevent deletion) | Low |
| 🟡 3 | Gate progress | "where is it blocked?" | Medium |
| 🟡 4 | Project health | Workflow visibility | Medium |
| 🟢 5 | File changes | Commit readiness | Low |
| 🔵 6 | Wisdom/agenda | Optional | Low |

---

## Data Access Patterns

All sources are **local, fast** (no API calls):

```bash
# Change metadata
cat ~/.local/share/opencode/plugins/advance/{id}/changes/{changeId}/change.json

# Worktree existence
ls ~/.local/share/opencode/worktree/{id}/

# Git metrics
git -C {path} status --short
git -C {path} rev-list --count HEAD..origin/main

# Specs
ls .adv/specs/
```

Refresh every 5 seconds (matches `status-interval` in theme.conf)

---

## Example Combined Left-Side Display

Compact layout (45 chars max):
```
tk-abc 🟢 5/9 | 🌳 wt-123 ↑3 | gates: ✓✓▶⊘
```

Minimal layout (30 chars max):
```
tk-abc 🟢 5/9 | 🌳 ↑3
```

Detailed layout (60+ chars):
```
openChadUpdate [5/9] 🟢 tk-abc | 🌳 wt ↑3 commits | gates: ✓prep ✓impl ▶review
```

Each component (task, worktree, gates) is independent and can be toggled via configuration.
