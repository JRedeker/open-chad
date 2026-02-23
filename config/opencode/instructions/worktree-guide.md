# Worktree Usage Guide

You have access to `worktree_create` and `worktree_delete` tools for isolated git worktree sessions.

## When to Create a Worktree

Use `worktree_create` when:
- **Risky refactors** — large structural changes that might break the codebase
- **Parallel experiments** — trying two different approaches to the same problem
- **Feature branches** — the user asks you to start a new feature in isolation
- **Exploratory work** — spiking on an idea without polluting the main branch

## When NOT to Create a Worktree

- Small, contained changes (bug fixes, config tweaks, single-file edits)
- When the user is already in a worktree session
- When the change is low-risk and easily reversible

## Behavior

- Default flow is inline: create worktree, then continue in the same agent session
- After creation, use the returned worktree path as `workdir` for subsequent tool calls
- Starting a separate tmux/OpenCode session is optional fallback for explicit multi-session workflows
- On delete, all changes are auto-committed before cleanup
- You can have multiple worktrees running simultaneously

## Post-Change Cleanup (Merge Before Delete)

**Never delete a worktree until its branch is merged to the default branch (e.g. `main` or `trunk`).**

After implementation is complete and the change is archived/signed off:

### Step 1: Verify the branch is clean

```bash
# In the worktree directory — no uncommitted changes
git status
# Should show "nothing to commit, working tree clean"
```

### Step 2: Merge to the default branch

```bash
# Switch back to the main working directory (not the worktree)
# Merge the change branch into the default branch
git checkout trunk        # or main — use the repo's default branch
git merge --no-edit change/{change-id}
```

Alternatively, if the project uses pull requests, push the branch and open a PR:

```bash
git push -u origin change/{change-id}
gh pr create --title "Archive {change-id}" --body "Merges completed change."
```

Wait for the PR to be merged before proceeding to deletion.

### Step 3: Verify the merge

```bash
# Confirm the change branch commits are reachable from the default branch
git log --oneline trunk..change/{change-id}
# Should return EMPTY (no commits ahead) — meaning everything is merged
```

### Step 4: Delete the worktree

Only after merge is confirmed:

```bash
worktree_delete reason: "Change {change-id} merged to default branch"
```

### Checklist

- [ ] All changes committed in the worktree branch
- [ ] Branch merged to default branch (direct merge or PR)
- [ ] Merge verified — no commits ahead of default branch
- [ ] `worktree_delete` called with reason

**If the merge is not yet complete, do NOT delete the worktree.** The worktree protects unmerged work from being lost.

## Always Ask First

Before creating a worktree, briefly explain WHY you think isolation is needed and confirm with the user.
