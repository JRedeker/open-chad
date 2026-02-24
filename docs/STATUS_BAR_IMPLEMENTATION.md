# Status Bar Left-Side Implementation Examples

This document shows how to extract each type of information for display on the status bar left side.

## 1. Task Progress (Highest Priority)

**Goal:** Display current task ID, TDD phase, and progress count

### Get Project ID (from .git)
```bash
#!/bin/bash
PROJECT_ID=$(git -C "$path" rev-list --max-parents=0 HEAD 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    exit 0  # Not a git repo
fi
```

### Get Active Change
```bash
CHANGE_DIR="$HOME/.local/share/opencode/plugins/advance/$PROJECT_ID/changes"

# Find the first (usually only) active change
CHANGE_JSON=$(find "$CHANGE_DIR" -name "change.json" -type f | head -1)

if [ ! -f "$CHANGE_JSON" ]; then
    exit 0  # No active changes
fi
```

### Extract Task Info
```bash
# Parse using jq
CHANGE_ID=$(jq -r '.id' "$CHANGE_JSON")
TASKS=$(jq '.tasks' "$CHANGE_JSON")
COMPLETED=$(echo "$TASKS" | jq '[.[] | select(.status == "completed")] | length')
TOTAL=$(echo "$TASKS" | jq 'length')

# Find current/in_progress task
CURRENT_TASK=$(echo "$TASKS" | jq '.[] | select(.status == "in_progress") | .id' | head -1 | tr -d '"')
TDD_PHASE=$(echo "$TASKS" | jq '.[] | select(.status == "in_progress") | .tdd_phase' | head -1 | tr -d '"')

# Convert TDD phase to emoji
case "$TDD_PHASE" in
    "red")   PHASE_EMOJI="🔴" ;;
    "green") PHASE_EMOJI="🟢" ;;
    "refactor") PHASE_EMOJI="🟡" ;;
    *)       PHASE_EMOJI="⚪" ;;
esac

# Output
printf '%s %s %d/%d' "${CURRENT_TASK:-$CHANGE_ID}" "$PHASE_EMOJI" "$COMPLETED" "$TOTAL"
```

### Result
```
tk-abc 🟢 5/9
```

---

## 2. Worktree Detection

**Goal:** Show if worktree is active and how many commits ahead

### Check for Active Worktree
```bash
WORKTREE_DIR="$HOME/.local/share/opencode/worktree/$PROJECT_ID"

if [ -d "$WORKTREE_DIR" ]; then
    # Find the actual git worktree path
    WORKTREE_PATH=$(find "$WORKTREE_DIR" -name ".git" -type f 2>/dev/null | head -1)
    
    if [ -n "$WORKTREE_PATH" ]; then
        WORKTREE_ROOT=$(dirname "$WORKTREE_PATH")
        
        # Count commits ahead of main/trunk
        COMMITS_AHEAD=$(git -C "$WORKTREE_ROOT" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
        
        # Get the change ID it's working on
        CHANGE_ID=$(basename "$(find "$WORKTREE_DIR" -name "change.json" -type f 2>/dev/null | head -1)" | cut -d. -f1)
        
        printf '🌳 %s ↑%d' "${CHANGE_ID:-wt}" "$COMMITS_AHEAD"
    fi
fi
```

### Result
```
🌳 change-123 ↑3
```

---

## 3. Gate Progress

**Goal:** Show 6-gate workflow status

### Extract Gate Status
```bash
DELTAS=$(jq '.deltas' "$CHANGE_JSON" 2>/dev/null)

# Gates in order: research, prep, implementation, review, harden, signoff
GATES=("research" "prep" "implementation" "review" "harden" "signoff")
SYMBOLS=""

for gate in "${GATES[@]}"; do
    STATUS=$(echo "$DELTAS" | jq -r ".gates[\"$gate\"]" 2>/dev/null)
    
    case "$STATUS" in
        "pass"|"completed")     SYMBOLS="${SYMBOLS}✓" ;;
        "fail"|"blocked")       SYMBOLS="${SYMBOLS}✗" ;;
        "in_progress"|"active") SYMBOLS="${SYMBOLS}▶" ;;
        *)                      SYMBOLS="${SYMBOLS}⊘" ;;
    esac
done

printf 'gates: %s' "$SYMBOLS"
```

### Result
```
gates: ✓✓▶⊘⊘⊘
```

---

## 4. Project Health Aggregate

**Goal:** Count active vs archived changes

### Count Changes by Status
```bash
CHANGE_DIR="$HOME/.local/share/opencode/plugins/advance/$PROJECT_ID/changes"
ARCHIVE_DIR="$HOME/.local/share/opencode/plugins/advance/$PROJECT_ID/archive"

ACTIVE=0
ARCHIVED=0

# Count active changes
for change_json in "$CHANGE_DIR"/*/change.json; do
    if [ -f "$change_json" ]; then
        STATUS=$(jq -r '.status' "$change_json" 2>/dev/null)
        if [ "$STATUS" = "in_progress" ] || [ "$STATUS" = "draft" ]; then
            ACTIVE=$((ACTIVE + 1))
        fi
    fi
done

# Count archived changes (not merged)
for change_json in "$ARCHIVE_DIR"/*/change.json; do
    if [ -f "$change_json" ]; then
        ARCHIVED=$((ARCHIVED + 1))
    fi
done

# Check how many archived are unmerged
UNMERGED=0
for worktree_dir in "$WORKTREE_DIR"/*; do
    if [ -d "$worktree_dir/.git" ]; then
        AHEAD=$(git -C "$worktree_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
        if [ "$AHEAD" -gt 0 ]; then
            UNMERGED=$((UNMERGED + 1))
        fi
    fi
done

printf 'proj: %d▶ %d✓ (%d pending merge)' "$ACTIVE" "$ARCHIVED" "$UNMERGED"
```

### Result
```
proj: 1▶ 2✓ (1 pending merge)
```

---

## 5. Git File Changes

**Goal:** Show unstaged, staged, and stashed changes

### Parse Git Status
```bash
# Unstaged changes
UNSTAGED=$(git -C "$path" diff --name-only 2>/dev/null | wc -l)

# Staged changes
STAGED=$(git -C "$path" diff --cached --name-only 2>/dev/null | wc -l)

# Stashed changes
STASHED=$(git -C "$path" stash list 2>/dev/null | wc -l)

# Commits ahead of upstream
COMMITS_AHEAD=$(git -C "$path" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)

# Output
if [ "$UNSTAGED" -gt 0 ] || [ "$STAGED" -gt 0 ]; then
    printf '+%d ~%d | %d stashed | ↑%d' "$STAGED" "$UNSTAGED" "$STASHED" "$COMMITS_AHEAD"
fi
```

### Result
```
+3 ~2 | 5 stashed | ↑2
```

---

## 6. Combined Script Template

Here's a template that combines multiple pieces:

```bash
#!/usr/bin/env bash
# status_left.sh - Left side status bar renderer

set -euo pipefail

path="${1:-}"

if [ -z "$path" ] || [ ! -d "$path/.git" ]; then
    git_dir=$(git -C "$path" rev-parse --git-dir 2>/dev/null) || exit 0
fi

PROJECT_ID=$(git -C "$path" rev-list --max-parents=0 HEAD 2>/dev/null) || exit 0
STATE_DIR="$HOME/.local/share/opencode/plugins/advance/$PROJECT_ID"

# 1. Task Progress
CHANGE_JSON=$(find "$STATE_DIR/changes" -name "change.json" -type f 2>/dev/null | head -1)
if [ -f "$CHANGE_JSON" ]; then
    COMPLETED=$(jq '[.tasks[] | select(.status == "completed")] | length' "$CHANGE_JSON" 2>/dev/null)
    TOTAL=$(jq '.tasks | length' "$CHANGE_JSON" 2>/dev/null)
    
    # Get current/first in-progress task
    CURRENT=$(jq -r '.tasks[] | select(.status == "in_progress") | .id' "$CHANGE_JSON" 2>/dev/null | head -1)
    TDD=$(jq -r '.tasks[] | select(.status == "in_progress") | .tdd_phase' "$CHANGE_JSON" 2>/dev/null | head -1)
    
    case "$TDD" in
        "red")   emoji="🔴" ;;
        "green") emoji="🟢" ;;
        *)       emoji="⚪" ;;
    esac
    
    output="${CURRENT:-?} $emoji $COMPLETED/$TOTAL"
fi

# 2. Worktree Alert
WORKTREE_DIR="$HOME/.local/share/opencode/worktree/$PROJECT_ID"
if [ -d "$WORKTREE_DIR" ]; then
    for wt_dir in "$WORKTREE_DIR"/*; do
        if [ -d "$wt_dir/.git" ] || [ -f "$wt_dir/.git" ]; then
            AHEAD=$(git -C "$wt_dir" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)
            output="$output | 🌳 ↑$AHEAD"
            break
        fi
    done
fi

printf '#[fg=colour245]%s' "$output"
```

---

## Performance Considerations

1. **JSON parsing:** Use `jq` (precompiled) not shell loops
2. **Caching:** Cache project ID early (never changes)
3. **Fallback:** Return dash (–) if data unavailable
4. **Timeout:** Wrap in `timeout 1s` to prevent hanging

```bash
# Fast path: use cached project ID
if [ -f /tmp/open-chad-project-id ]; then
    PROJECT_ID=$(cat /tmp/open-chad-project-id)
else
    PROJECT_ID=$(git -C "$path" rev-list --max-parents=0 HEAD 2>/dev/null)
    echo "$PROJECT_ID" > /tmp/open-chad-project-id
fi
```

---

## Testing Extraction

Quick test of data extraction:

```bash
# Test task progress
cat ~/.local/share/opencode/plugins/advance/{id}/changes/*/change.json | \
  jq '{id, status, completed: [.tasks[] | select(.status=="completed")] | length, total: .tasks | length}'

# Test worktree
ls -d ~/.local/share/opencode/worktree/{id}/*/

# Test gates (if deltas field exists)
cat ~/.local/share/opencode/plugins/advance/{id}/changes/*/change.json | jq '.deltas'
```

---

## Integration with theme.conf

Update status-format[1] in lib/theme.conf:

```tmux
set -g 'status-format[1]' \
  '#[align=left,bg=colour233]#[fg=colour107]▌#[fg=colour186]▌#[fg=colour173]▌#[fg=colour131]▌#[bg=colour233] ' \
  '#[nobold]#(~/dev/open-chad/lib/title_parser.sh "#{window_name}") ' \
  '#[nobold,fg=colour245]#(~/dev/open-chad/lib/status_left.sh "#{pane_current_path}") ' \
  '#[align=right,nobold,fg=colour245]#(~/dev/open-chad/lib/status_right.sh "#{pane_current_path}")'
```

This adds `status_left.sh` between the title parser and the right-side metrics.

