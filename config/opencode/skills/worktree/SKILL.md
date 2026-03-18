---
name: worktree
description: "Git worktree workflow guidance — use when creating, navigating, merging, or deleting worktrees. Covers when to isolate, merge-before-delete protocol, and tmux navigation."
license: MIT
metadata:
  priority: medium
  replaces: none
---

## When to Load This Skill

Load this skill when you need to **create, manage, or clean up git worktrees**. Covers decision criteria, merge protocol, and tmux navigation hints.

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
- **CRITICAL: After creation, you MUST immediately switch ALL tool calls to use the returned worktree path as `workdir`.** Do not run any more commands against the original directory. This includes bash, read, edit, glob, grep — everything.
- On delete, all changes are auto-committed before cleanup. Pass the `branch` arg to `worktree_delete`.
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
worktree_delete branch: "change/{change-id}" reason: "Change {change-id} merged to default branch"
```

### Checklist

- [ ] All changes committed in the worktree branch
- [ ] Branch merged to default branch (direct merge or PR)
- [ ] Merge verified — no commits ahead of default branch
- [ ] `worktree_delete` called with reason

**If the merge is not yet complete, do NOT delete the worktree.** The worktree protects unmerged work from being lost.

## Inline Mode (Default)

Worktrees default to **inline mode**: no new terminal or tmux window is opened.
After `worktree_create` succeeds, use the returned path as `workdir` for all
subsequent tool calls (bash, read, edit, glob, grep, etc.).

When deleting an inline worktree, pass the `branch` argument to `worktree_delete`
so the plugin knows which worktree to remove.

If a project sets `"inline": false` in `.opencode/worktree.jsonc`, the old
behavior is restored (new tmux window / terminal tab with a separate OpenCode
instance).

## Ask Only When Needed

Before creating a worktree, explain why isolation helps. Ask the user only when the decision is materially ambiguous or when the action is destructive/irreversible. Otherwise, proceed with the safest reasonable default.

## Keywords
worktree, git worktree, branch isolation, parallel development, merge before delete,
worktree create, worktree delete, tmux navigation, feature branch, risky refactor,
exploratory work, worktree cleanup
